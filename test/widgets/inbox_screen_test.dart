import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/home/widgets/inbox_screen.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:matrix/matrix.dart' show Client, GetNotificationsResponse, MatrixEvent;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
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

  Widget buildTestWidget() {
    return ChangeNotifierProvider<InboxController>.value(
      value: controller,
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

      // Room name (falls back to roomId when no room found)
      expect(find.text('!r1:x'), findsOneWidget);
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

      // Stub for mentions filter
      when(mockClient.getNotifications(
        limit: anyNamed('limit'),
        only: 'highlight',
        from: anyNamed('from'),
      ),).thenAnswer((_) => Future.microtask(() => _makeResponse([])));

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
        ChangeNotifierProvider<InboxController>.value(
          value: controller,
          child: const MaterialApp(home: Scaffold()),
        ),
      );
      await tester.pumpAndSettle();

      // Polling should have been stopped — no exception from timer
    });
  });
}
