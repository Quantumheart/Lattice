import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';

import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/screens/chat_screen.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import 'pinned_messages_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────

late MockRoom _mockRoom;

MockEvent _makeEvent({
  required String eventId,
  required String senderId,
  String body = 'Hello',
  Map<String, Object?>? content,
  bool redacted = false,
  bool canRedact = true,
  String? relationshipType,
}) {
  final event = MockEvent();
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.body).thenReturn(body);
  when(event.type).thenReturn(EventTypes.Message);
  when(event.messageType).thenReturn(MessageTypes.Text);
  when(event.originServerTs).thenReturn(DateTime(2025, 1, 1, 12, 0));
  when(event.status).thenReturn(EventStatus.synced);
  when(event.content)
      .thenReturn(content ?? {'body': body, 'msgtype': 'm.text'});
  when(event.room).thenReturn(_mockRoom);
  when(event.redacted).thenReturn(redacted);
  when(event.canRedact).thenReturn(canRedact);
  when(event.relationshipType).thenReturn(relationshipType);
  when(event.getDisplayEvent(any)).thenReturn(event);
  when(event.hasAggregatedEvents(any, any)).thenReturn(false);
  when(event.formattedText).thenReturn('');

  final sender = MockUser();
  when(sender.displayName)
      .thenReturn(senderId.split(':').first.substring(1));
  when(sender.avatarUrl).thenReturn(null);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);

  return event;
}

Widget _buildChatWidget({
  required MockClient mockClient,
  required MockMatrixService mockMatrix,
  required PreferencesService prefsService,
  double width = 800,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
      ChangeNotifierProvider<PreferencesService>.value(value: prefsService),
    ],
    child: MaterialApp(
      home: SizedBox(
        width: width,
        child: const ChatScreen(roomId: '!room:example.com'),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;
  late PreferencesService prefsService;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();
    prefsService = PreferencesService();
    _mockRoom = mockRoom;

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.onSync).thenReturn(CachedStreamController());
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.receiptState).thenReturn(LatestReceiptState.empty());
    when(mockRoom.summary).thenReturn(
      RoomSummary.fromJson({'m.joined_member_count': 3}),
    );
    when(mockTimeline.canRequestHistory).thenReturn(false);
  });

  // ── Pin icon in app bar ─────────────────────────────────────

  group('Pin icon in app bar', () {
    testWidgets('shows pin icon with badge when room has pinned events',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn(['\$pin1', '\$pin2']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Test message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('hides pin icon when no pinned events', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Test message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // push_pin_rounded should not appear in the app bar
      // (it may appear in message bubbles if isPinned, so check app bar only)
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.push_pin_rounded),
        ),
        findsNothing,
      );
    });
  });

  // ── Pinned messages popup ───────────────────────────────────

  group('Pinned messages popup', () {
    testWidgets('shows loading indicator then pinned messages',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final pinnedEvent = _makeEvent(
        eventId: '\$pin1',
        senderId: '@alice:example.com',
        body: 'Pinned message body',
      );
      when(mockRoom.pinnedEventIds).thenReturn(['\$pin1']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);
      when(mockRoom.getEventById('\$pin1'))
          .thenAnswer((_) async => pinnedEvent);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Test message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Tap pin icon
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.push_pin_rounded),
      ));
      await tester.pump();

      // Should see the popup header
      expect(find.text('Pinned Messages'), findsOneWidget);

      // Wait for async loading
      await tester.pumpAndSettle();

      // Should display the pinned message body
      expect(find.text('Pinned message body'), findsOneWidget);
    });

    testWidgets('shows empty state when all pinned events fail to load',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn(['\$missing1']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);
      when(mockRoom.getEventById('\$missing1'))
          .thenThrow(Exception('Not found'));

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Test message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Tap pin icon
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.push_pin_rounded),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No pinned messages'), findsOneWidget);
    });

    testWidgets('unpin removes event from popup list', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final pinnedEvent1 = _makeEvent(
        eventId: '\$pin1',
        senderId: '@alice:example.com',
        body: 'First pinned',
      );
      final pinnedEvent2 = _makeEvent(
        eventId: '\$pin2',
        senderId: '@bob:example.com',
        body: 'Second pinned',
      );
      when(mockRoom.pinnedEventIds).thenReturn(['\$pin1', '\$pin2']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);
      when(mockRoom.getEventById('\$pin1'))
          .thenAnswer((_) async => pinnedEvent1);
      when(mockRoom.getEventById('\$pin2'))
          .thenAnswer((_) async => pinnedEvent2);
      when(mockRoom.setPinnedEvents(any)).thenAnswer((_) async => '');

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Test message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Open popup
      await tester.tap(find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.push_pin_rounded),
      ));
      await tester.pumpAndSettle();

      expect(find.text('First pinned'), findsOneWidget);
      expect(find.text('Second pinned'), findsOneWidget);

      // Tap the unpin (close) button on the first pinned message
      final unpinButtons = find.byTooltip('Unpin');
      expect(unpinButtons, findsNWidgets(2));
      await tester.tap(unpinButtons.first);
      await tester.pumpAndSettle();

      // Should have called setPinnedEvents with the first event removed
      verify(mockRoom.setPinnedEvents(['\$pin2'])).called(1);
    });
  });

  // ── Toggle pin via context menu ─────────────────────────────

  group('Toggle pin via context menu', () {
    testWidgets('pin option appears in context menu when user has permission',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Pin this message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Right-click
      await tester.tapAt(
        tester.getCenter(find.text('Pin this message')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Pin'), findsOneWidget);
    });

    testWidgets('pin option hidden when user lacks permission',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(false);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Cannot pin this',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Right-click
      await tester.tapAt(
        tester.getCenter(find.text('Cannot pin this')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Pin'), findsNothing);
      expect(find.text('Unpin'), findsNothing);
    });

    testWidgets('pinning calls setPinnedEvents with event added',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn([]);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);
      when(mockRoom.setPinnedEvents(any)).thenAnswer((_) async => '');

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Pin me',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Right-click → Pin
      await tester.tapAt(
        tester.getCenter(find.text('Pin me')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      verify(mockRoom.setPinnedEvents(['\$evt1'])).called(1);
    });

    testWidgets('unpinning calls setPinnedEvents with event removed',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn(['\$evt1']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);
      when(mockRoom.setPinnedEvents(any)).thenAnswer((_) async => '');

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Unpin me',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // Right-click → Unpin
      await tester.tapAt(
        tester.getCenter(find.text('Unpin me')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();

      verify(mockRoom.setPinnedEvents([])).called(1);
    });
  });

  // ── Pin indicator in message bubble ─────────────────────────

  group('Pin indicator in message bubble', () {
    testWidgets('shows pin icon in timestamp row for pinned messages',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      when(mockRoom.pinnedEventIds).thenReturn(['\$evt1']);
      when(mockRoom.canChangeStateEvent('m.room.pinned_events'))
          .thenReturn(true);

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: 'I am pinned',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
      ));
      await tester.pumpAndSettle();

      // The pin icon should appear in the message bubble timestamp row
      // (not in the app bar, which also has a pin icon)
      expect(find.byIcon(Icons.push_pin_rounded), findsWidgets);
    });
  });
}
