import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/screens/chat_screen.dart';
import 'package:lattice/widgets/chat/edit_preview_banner.dart';
import 'package:lattice/widgets/chat/message_bubble.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import 'message_actions_test.mocks.dart';

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
  double width = 400,
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

Widget _buildBubble({
  required MockEvent event,
  required bool isMe,
  Timeline? timeline,
  VoidCallback? onReply,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return ChangeNotifierProvider<PreferencesService>.value(
    value: PreferencesService(),
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: MessageBubble(
            event: event,
            isMe: isMe,
            isFirst: true,
            timeline: timeline,
            onReply: onReply,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ),
    ),
  );
}

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
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.summary).thenReturn(
      RoomSummary.fromJson({'m.joined_member_count': 3}),
    );
    when(mockTimeline.canRequestHistory).thenReturn(false);
  });

  // ── EditPreviewBanner ──────────────────────────────────────

  group('EditPreviewBanner', () {
    testWidgets('shows edit icon and message body', (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Original message text',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditPreviewBanner(
            event: event,
            onCancel: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.text('Editing'), findsOneWidget);
      expect(find.text('Original message text'), findsOneWidget);
    });

    testWidgets('cancel button calls onCancel', (tester) async {
      bool cancelled = false;
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Some message',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditPreviewBanner(
            event: event,
            onCancel: () => cancelled = true,
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cancelled, isTrue);
    });

    testWidgets('strips reply fallback from body', (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: '> <@alice:example.com> quoted\n\nActual text',
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EditPreviewBanner(
            event: event,
            onCancel: () {},
          ),
        ),
      ));

      expect(find.text('Actual text'), findsOneWidget);
    });
  });

  // ── Redacted message rendering ─────────────────────────────

  group('Redacted message rendering', () {
    testWidgets('shows "You deleted this message" for own redacted message',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: '',
        redacted: true,
      );
      when(event.redactedBecause).thenReturn(null);

      await tester.pumpWidget(_buildBubble(event: event, isMe: true));
      await tester.pumpAndSettle();

      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('shows "This message was deleted" for other user self-redact',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: '',
        redacted: true,
      );
      final redactEvent = _makeEvent(
        eventId: '\$redact1',
        senderId: '@alice:example.com',
      );
      when(event.redactedBecause).thenReturn(redactEvent);

      await tester.pumpWidget(_buildBubble(event: event, isMe: false));
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('shows "Deleted by moderator" for moderator redaction',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: '',
        redacted: true,
      );
      final redactEvent = _makeEvent(
        eventId: '\$redact1',
        senderId: '@mod:example.com',
      );
      when(event.redactedBecause).thenReturn(redactEvent);

      final modUser = MockUser();
      when(modUser.displayName).thenReturn('Moderator');
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@mod:example.com'))
          .thenReturn(modUser);

      await tester.pumpWidget(_buildBubble(event: event, isMe: false));
      await tester.pumpAndSettle();

      expect(find.text('Deleted by Moderator'), findsOneWidget);
    });
  });

  // ── Edited message rendering ───────────────────────────────

  group('Edited message rendering', () {
    testWidgets('shows (edited) indicator when message has edits',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Updated text',
      );
      when(event.hasAggregatedEvents(mockTimeline, RelationshipTypes.edit))
          .thenReturn(true);

      await tester.pumpWidget(_buildBubble(
        event: event,
        isMe: true,
        timeline: mockTimeline,
      ));
      await tester.pumpAndSettle();

      expect(find.text('(edited)'), findsOneWidget);
    });

    testWidgets('uses display event body for edited messages', (tester) async {
      final originalEvent = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Original text',
      );
      final editedEvent = _makeEvent(
        eventId: '\$edit1',
        senderId: '@me:example.com',
        body: 'Edited text',
      );
      when(originalEvent.getDisplayEvent(mockTimeline))
          .thenReturn(editedEvent);
      when(originalEvent.hasAggregatedEvents(
              mockTimeline, RelationshipTypes.edit))
          .thenReturn(true);

      await tester.pumpWidget(_buildBubble(
        event: originalEvent,
        isMe: true,
        timeline: mockTimeline,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edited text'), findsOneWidget);
      expect(find.text('Original text'), findsNothing);
    });
  });

  // ── Desktop context menu ───────────────────────────────────

  group('Desktop context menu', () {
    testWidgets('shows Edit option only for own messages', (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'My message',
      );

      await tester.pumpWidget(_buildBubble(
        event: event,
        isMe: true,
        onReply: () {},
        onEdit: () {},
        onDelete: () {},
      ));
      await tester.pumpAndSettle();

      // Right-click to show context menu.
      final bubble = find.text('My message');
      await tester.tapAt(
        tester.getCenter(bubble),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('shows "Remove" label for other users messages',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@alice:example.com',
        body: 'Their message',
      );

      await tester.pumpWidget(_buildBubble(
        event: event,
        isMe: false,
        onReply: () {},
        onDelete: () {},
      ));
      await tester.pumpAndSettle();

      // Right-click.
      final bubble = find.text('Their message');
      await tester.tapAt(
        tester.getCenter(bubble),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Remove'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('copy uses edited display event body', (tester) async {
      // Track clipboard data.
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final originalEvent = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Original text',
      );
      final editedEvent = _makeEvent(
        eventId: '\$edit1',
        senderId: '@me:example.com',
        body: 'Edited text',
      );
      when(originalEvent.getDisplayEvent(mockTimeline))
          .thenReturn(editedEvent);

      await tester.pumpWidget(_buildBubble(
        event: originalEvent,
        isMe: true,
        timeline: mockTimeline,
        onReply: () {},
      ));
      await tester.pumpAndSettle();

      // Right-click.
      final bubble = find.text('Edited text');
      await tester.tapAt(
        tester.getCenter(bubble),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      // Tap copy.
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'Edited text');
    });
  });

  // ── Edit flow in ChatScreen ────────────────────────────────

  group('ChatScreen edit flow', () {
    testWidgets('edit preview banner appears after triggering edit',
        (tester) async {
      // Use desktop width to access right-click context menu.
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'My message to edit',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Right-click the message.
      final msg = find.text('My message to edit');
      expect(msg, findsOneWidget);
      await tester.tapAt(
        tester.getCenter(msg),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      // Tap Edit.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Edit preview banner should appear.
      expect(find.text('Editing'), findsOneWidget);
      expect(find.text('Edit message…'), findsOneWidget);

      // Text field should be pre-filled with the message body.
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'My message to edit');
    });

    testWidgets('cancel edit clears banner and text field', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'My message',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Trigger edit via right-click.
      await tester.tapAt(
        tester.getCenter(find.text('My message')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Editing'), findsOneWidget);

      // Tap cancel.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Editing'), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('sending edit passes editEventId to sendTextEvent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Original text',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);
      when(mockRoom.sendTextEvent(
        any,
        inReplyTo: anyNamed('inReplyTo'),
        editEventId: anyNamed('editEventId'),
      )).thenAnswer((_) async => '\$sent1');

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Trigger edit.
      await tester.tapAt(
        tester.getCenter(find.text('Original text')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Modify text and send.
      await tester.enterText(find.byType(TextField), 'Updated text');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verify(mockRoom.sendTextEvent(
        'Updated text',
        inReplyTo: null,
        editEventId: '\$evt1',
      )).called(1);
    });
  });

  // ── Delete flow in ChatScreen ──────────────────────────────

  group('ChatScreen delete flow', () {
    testWidgets('delete shows confirmation dialog with "Delete" for own msg',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Delete me',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Right-click → Delete.
      await tester.tapAt(
        tester.getCenter(find.text('Delete me')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      // The menu should show "Delete" not "Remove" since this is our own message.
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog.
      expect(find.text('Delete message?'), findsOneWidget);
      expect(
        find.text('This message will be permanently deleted for everyone.'),
        findsOneWidget,
      );
    });

    testWidgets('confirming delete calls redactEvent', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Delete me',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);
      when(mockRoom.redactEvent('\$evt1'))
          .thenAnswer((_) async => '\$redact1');

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Right-click → Delete.
      await tester.tapAt(
        tester.getCenter(find.text('Delete me')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(mockRoom.redactEvent('\$evt1')).called(1);
    });

    testWidgets('cancelling delete dialog does not call redactEvent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Do not delete',
      );
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Right-click → Delete → Cancel.
      await tester.tapAt(
        tester.getCenter(find.text('Do not delete')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockRoom.redactEvent(any));
    });
  });

  // ── Redacted messages disable interactions ─────────────────

  group('Redacted message interactions', () {
    testWidgets('redacted messages do not show context menu on desktop',
        (tester) async {
      final event = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: '',
        redacted: true,
      );
      when(event.redactedBecause).thenReturn(null);

      // Build with no action callbacks (as ChatScreen does for redacted).
      await tester.pumpWidget(_buildBubble(
        event: event,
        isMe: true,
      ));
      await tester.pumpAndSettle();

      // Right-click should not produce a context menu with Reply/Edit/Delete.
      final msg = find.text('You deleted this message');
      await tester.tapAt(
        tester.getCenter(msg),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });
  });

  // ── Edit events filtered from timeline ─────────────────────

  group('Edit events filtered from visible timeline', () {
    testWidgets('edit relation events are not shown in message list',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final original = _makeEvent(
        eventId: '\$evt1',
        senderId: '@me:example.com',
        body: 'Original message',
      );
      final editEvent = _makeEvent(
        eventId: '\$edit1',
        senderId: '@me:example.com',
        body: 'Edited message',
        relationshipType: RelationshipTypes.edit,
      );
      when(mockTimeline.events).thenReturn([editEvent, original]);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((_) async => mockTimeline);

      await tester.pumpWidget(_buildChatWidget(
        mockClient: mockClient,
        mockMatrix: mockMatrix,
        prefsService: prefsService,
        width: 800,
      ));
      await tester.pumpAndSettle();

      // Only the original message should be visible, not the edit event.
      expect(find.text('Original message'), findsOneWidget);
      expect(find.text('Edited message'), findsNothing);
    });
  });
}
