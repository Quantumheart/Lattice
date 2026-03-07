import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'inbox_controller_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

Notification _makeNotification({
  required String eventId,
  required String roomId,
  bool read = false,
  int ts = 1000,
}) {
  return Notification(
    actions: [],
    event: MatrixEvent(
      type: 'm.room.message',
      content: {'body': 'hello', 'msgtype': 'm.text'},
      senderId: '@alice:example.com',
      eventId: eventId,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      roomId: roomId,
    ),
    read: read,
    roomId: roomId,
    ts: ts,
  );
}

GetNotificationsResponse _makeResponse(
  List<Notification> notifications, {
  String? nextToken,
}) {
  return GetNotificationsResponse(
    notifications: notifications,
    nextToken: nextToken,
  );
}

void main() {
  late MockClient mockClient;
  late InboxController controller;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.getRoomById(any)).thenReturn(null);
    controller = InboxController(client: mockClient);
  });

  tearDown(() {
    controller.dispose();
  });

  // ── fetch() happy path ──────────────────────────────────────

  group('fetch()', () {
    test('populates grouped, transitions isLoading, clears error', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      expect(controller.isLoading, isFalse);

      await controller.fetch();

      expect(controller.isLoading, isFalse);
      expect(controller.error, isNull);
      expect(controller.grouped, hasLength(2));
      expect(controller.grouped[0].roomId, '!r1:x');
      expect(controller.grouped[0].notifications, hasLength(2));
      expect(controller.grouped[1].roomId, '!r2:x');
    });

    test('generation counter discards stale fetch results', () async {
      final completer1 = Completer<GetNotificationsResponse>();
      final completer2 = Completer<GetNotificationsResponse>();

      var callCount = 0;
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) {
        callCount++;
        if (callCount == 1) return completer1.future;
        return completer2.future;
      });

      // Start first fetch
      final future1 = controller.fetch();

      // Start second fetch (via setFilter), which increments generation
      controller.setFilter(InboxFilter.mentions);

      // Complete second fetch first with new data
      completer2.complete(_makeResponse([
        _makeNotification(eventId: 'new1', roomId: '!new:x'),
      ]),);

      // Wait for second fetch to finish
      // (setFilter calls fetch internally, we need to let it settle)
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Now complete the first (stale) fetch
      completer1.complete(_makeResponse([
        _makeNotification(eventId: 'old1', roomId: '!old:x'),
      ]),);

      await future1;

      // The stale results should be discarded, new results should be present
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });

    test('sets error on exception', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenThrow(Exception('network'));

      await controller.fetch();

      expect(controller.error, contains('network'));
      expect(controller.grouped, isEmpty);
    });
  });

  // ── setFilter() ─────────────────────────────────────────────

  group('setFilter()', () {
    test('clears grouped, triggers re-fetch', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      expect(controller.grouped, hasLength(1));

      // Now change filter
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: 'highlight',
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      controller.setFilter(InboxFilter.mentions);

      // Wait for async fetch to complete
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(controller.filter, InboxFilter.mentions);
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!r2:x');
    });

    test('does nothing when setting same filter', () async {
      final notifications = <void Function()>[];
      controller.addListener(() => notifications.add(() {}));

      controller.setFilter(InboxFilter.all); // same as default
      expect(notifications, isEmpty);
    });
  });

  // ── loadMore() ──────────────────────────────────────────────

  group('loadMore()', () {
    test('merges paginated results into existing groups', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();
      expect(controller.hasMore, isTrue);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e2', roomId: '!r1:x'),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      await controller.loadMore();

      expect(controller.grouped, hasLength(2));
      expect(controller.grouped[0].notifications, hasLength(2));
    });

    test('stale loadMore is discarded on filter change', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();

      final loadMoreCompleter = Completer<GetNotificationsResponse>();
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) => loadMoreCompleter.future);

      final loadFuture = controller.loadMore();

      // Change filter while loadMore is in-flight
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: 'highlight',
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'new1', roomId: '!new:x'),
          ]),);
      controller.setFilter(InboxFilter.mentions);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Complete the stale loadMore
      loadMoreCompleter.complete(_makeResponse([
        _makeNotification(eventId: 'stale1', roomId: '!stale:x'),
      ]),);
      await loadFuture;

      // Stale results should be discarded
      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });
  });

  // ── markRoomAsRead() ────────────────────────────────────────

  group('markRoomAsRead()', () {
    test('calls setReadMarker with correct eventId and refreshes', () async {
      final mockRoom = MockRoom();
      when(mockRoom.lastEvent).thenReturn(null);
      when(mockRoom.setReadMarker(any)).thenAnswer((_) async {});
      when(mockClient.getRoomById('!r1:x')).thenReturn(mockRoom);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      await controller.markRoomAsRead('!r1:x');

      verify(mockRoom.setReadMarker('e1')).called(1);
    });
  });

  // ── Polling ────────────────────────────────────────────────

  group('startPolling / stopPolling', () {
    test('_pollOnce fires at 7s intervals', () {
      fakeAsync((async) {
        when(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).thenAnswer((_) async => _makeResponse([]));

        controller.startPolling();

        // No calls at t=0
        verifyNever(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),);

        // Advance to 7s
        async.elapse(const Duration(seconds: 7));
        verify(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).called(1);

        // Advance to 14s
        async.elapse(const Duration(seconds: 7));
        verify(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),).called(1);

        controller.stopPolling();

        // Reset interaction count, then verify no more calls
        clearInteractions(mockClient);
        async.elapse(const Duration(seconds: 14));
        verifyNever(mockClient.getNotifications(
          limit: anyNamed('limit'),
          only: anyNamed('only'),
        ),);
      });
    });
  });

  // ── dispose ────────────────────────────────────────────────

  group('dispose', () {
    test('no crash when async fetch completes after dispose', () async {
      // Use a separate controller for this test to avoid double-dispose
      final disposableController = InboxController(client: mockClient);
      final completer = Completer<GetNotificationsResponse>();

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) => completer.future);

      final future = disposableController.fetch();
      disposableController.dispose();

      // Complete the fetch after dispose — should not throw
      completer.complete(_makeResponse([
        _makeNotification(eventId: 'e1', roomId: '!r1:x'),
      ]),);

      await future; // No exception
    });
  });

  // ── unreadCount ────────────────────────────────────────────

  group('unreadCount', () {
    test('cached count matches actual unread after fetch', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
            _makeNotification(eventId: 'e2', roomId: '!r1:x', read: true),
            _makeNotification(eventId: 'e3', roomId: '!r2:x'),
          ]),);

      expect(controller.unreadCount, 0);

      await controller.fetch();

      expect(controller.unreadCount, 2);
    });

    test('unreadCount updates after loadMore', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse(
            [_makeNotification(eventId: 'e1', roomId: '!r1:x')],
            nextToken: 'page2',
          ),);

      await controller.fetch();
      expect(controller.unreadCount, 1);

      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        from: 'page2',
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e2', roomId: '!r2:x'),
          ]),);

      await controller.loadMore();
      expect(controller.unreadCount, 2);
    });
  });

  // ── updateClient() ────────────────────────────────────────

  group('updateClient()', () {
    test('resets state and triggers new fetch', () async {
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'e1', roomId: '!r1:x'),
          ]),);

      await controller.fetch();
      expect(controller.grouped, hasLength(1));

      final newClient = MockClient();
      when(newClient.getRoomById(any)).thenReturn(null);
      when(newClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
      ),).thenAnswer((_) async => _makeResponse([
            _makeNotification(eventId: 'new1', roomId: '!new:x'),
          ]),);

      controller.updateClient(newClient);

      // Wait for async fetch
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(controller.grouped, hasLength(1));
      expect(controller.grouped[0].roomId, '!new:x');
    });
  });
}
