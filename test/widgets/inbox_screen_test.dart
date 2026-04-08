import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/home/widgets/inbox_screen.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client, GetNotificationsResponse, MatrixEvent, Membership, Room, SyncUpdate, User;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'inbox_screen_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

matrix_sdk.Notification _makeNotification({
  required String eventId,
  required String roomId,
  bool read = false,
  int ts = 1000,
  String body = 'hello',
  String senderId = '@alice:example.com',
}) {
  return matrix_sdk.Notification(
    actions: [],
    event: MatrixEvent(
      type: 'm.room.message',
      content: {'body': body, 'msgtype': 'm.text'},
      senderId: senderId,
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
  List<matrix_sdk.Notification> notifications, {
  String? nextToken,
}) {
  return GetNotificationsResponse(
    notifications: notifications,
    nextToken: nextToken,
  );
}

class _FakeMatrixService extends ChangeNotifier implements MatrixService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockClient mockClient;
  late InboxController controller;
  late _FakeMatrixService fakeMatrix;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    final joinedRoom = MockRoom();
    when(joinedRoom.membership).thenReturn(Membership.join);
    when(joinedRoom.client).thenReturn(mockClient);
    when(joinedRoom.getLocalizedDisplayname(any)).thenReturn('Test Room');
    when(joinedRoom.unsafeGetUserFromMemoryOrFallback(any)).thenReturn(
      User('@alice:example.com', displayName: 'Alice', room: joinedRoom),
    );
    when(mockClient.getRoomById(any)).thenReturn(joinedRoom);
    controller = InboxController(client: mockClient);
    fakeMatrix = _FakeMatrixService();
    selectionService = SelectionService(client: mockClient);
  });

  tearDown(() {
    controller.dispose();
    fakeMatrix.dispose();
    selectionService.dispose();
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<InboxController>.value(value: controller),
        ChangeNotifierProvider<MatrixService>.value(value: fakeMatrix),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
      ],
      child: const MaterialApp(
        home: InboxScreen(),
      ),
    );
  }

  /// Stub getNotifications so that the initial fetch triggered from initState
  /// completes asynchronously (after the build phase). Use a real `Future`
  /// with a microtask gap to avoid "setState during build" errors.
  void stubFetchAsync(GetNotificationsResponse response) {
    when(mockClient.getNotifications(
      limit: anyNamed('limit'),
      only: anyNamed('only'),
      from: anyNamed('from'),
    ),).thenAnswer((_) => Future.microtask(() => response));
  }

  group('InboxScreen', () {
    testWidgets('initial fetch triggered when grouped is empty',
        (tester) async {
      stubFetchAsync(_makeResponse([
        _makeNotification(eventId: 'e1', roomId: '!r1:x'),
      ]),);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      verify(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
        from: anyNamed('from'),
      ),).called(greaterThanOrEqualTo(1));
    });

    testWidgets('loading state shows CircularProgressIndicator',
        (tester) async {
      // Use a completer to hold the fetch indefinitely
      final completer = Completer<GetNotificationsResponse>();
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: anyNamed('only'),
        from: anyNamed('from'),
      ),).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      // Pump once to let initState's fetch trigger isLoading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending timers
      completer.complete(_makeResponse([]));
      await tester.pumpAndSettle();
    });

    testWidgets('empty state shows appropriate message', (tester) async {
      stubFetchAsync(_makeResponse([]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No notifications'), findsOneWidget);
    });

    testWidgets('notification groups render with room name and event body',
        (tester) async {
      stubFetchAsync(_makeResponse([
        _makeNotification(
          eventId: 'e1',
          roomId: '!r1:x',
          body: 'Test message content',
        ),
      ]),);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Room name from stubbed getLocalizedDisplayname
      expect(find.text('Test Room'), findsOneWidget);
      // Event body
      expect(find.text('Test message content'), findsOneWidget);
    });

    testWidgets('filter chip switching calls setFilter and UI updates',
        (tester) async {
      stubFetchAsync(_makeResponse([
        _makeNotification(eventId: 'e1', roomId: '!r1:x'),
      ]),);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      stubFetchAsync(_makeResponse([]));

      await tester.tap(find.text('Mentions'));
      await tester.pumpAndSettle();

      expect(controller.filter, InboxFilter.mentions);
    });

    testWidgets('polling stopped on dispose', (tester) async {
      stubFetchAsync(_makeResponse([]));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate away to trigger dispose of InboxScreen (not the controller)
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InboxController>.value(value: controller),
            ChangeNotifierProvider<MatrixService>.value(value: fakeMatrix),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
          ],
          child: const MaterialApp(home: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();

      // Polling should have been stopped — no exception from timer
    });
  });
}
