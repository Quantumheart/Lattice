import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/widgets/chat/message_bubble.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Client>(),
])
import 'message_bubble_bad_encrypted_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────

late MockRoom _mockRoom;

MockEvent _makeBadEncryptedEvent({
  bool canRequestSession = false,
  String? sessionId,
  String? senderKey,
}) {
  final event = MockEvent();
  when(event.eventId).thenReturn('\$enc1');
  when(event.senderId).thenReturn('@other:example.com');
  when(event.body)
      .thenReturn('The sender has not sent us the session key.');
  when(event.type).thenReturn(EventTypes.Encrypted);
  when(event.messageType).thenReturn(MessageTypes.BadEncrypted);
  when(event.originServerTs).thenReturn(DateTime(2025, 1, 1, 12, 0));
  when(event.status).thenReturn(EventStatus.synced);
  when(event.content).thenReturn({
    'msgtype': MessageTypes.BadEncrypted,
    'body': 'The sender has not sent us the session key.',
    'can_request_session': canRequestSession,
    if (sessionId != null) 'session_id': sessionId,
    if (senderKey != null) 'sender_key': senderKey,
  });
  when(event.room).thenReturn(_mockRoom);
  when(event.redacted).thenReturn(false);
  when(event.canRedact).thenReturn(true);
  when(event.relationshipType).thenReturn(null);
  when(event.getDisplayEvent(any)).thenReturn(event);
  when(event.hasAggregatedEvents(any, any)).thenReturn(false);
  when(event.formattedText).thenReturn('');

  final sender = MockUser();
  when(sender.displayName).thenReturn('other');
  when(sender.avatarUrl).thenReturn(null);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);

  return event;
}

Widget _buildBubble({
  required MockEvent event,
  bool isMe = false,
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
          ),
        ),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────

void main() {
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
    _mockRoom = MockRoom();

    when(_mockRoom.id).thenReturn('!room:example.com');
    when(_mockRoom.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  testWidgets('shows lock icon and unable-to-decrypt text', (tester) async {
    final event = _makeBadEncryptedEvent();
    await tester.pumpWidget(_buildBubble(event: event));
    await tester.pump();

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Unable to decrypt this message'), findsOneWidget);
  });

  testWidgets('does not show raw error body text', (tester) async {
    final event = _makeBadEncryptedEvent();
    await tester.pumpWidget(_buildBubble(event: event));
    await tester.pump();

    expect(
      find.text('The sender has not sent us the session key.'),
      findsNothing,
    );
  });

  testWidgets('hides Retry when can_request_session is false',
      (tester) async {
    final event = _makeBadEncryptedEvent(canRequestSession: false);
    await tester.pumpWidget(_buildBubble(event: event));
    await tester.pump();

    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('shows Retry when can_request_session is true', (tester) async {
    final event = _makeBadEncryptedEvent(
      canRequestSession: true,
      sessionId: 'abc123',
      senderKey: 'xyz789',
    );
    await tester.pumpWidget(_buildBubble(event: event));
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping Retry does not throw', (tester) async {
    // encryption is null by default on MockClient, so maybeAutoRequest
    // is a no-op — we just verify the tap path doesn't crash.
    final event = _makeBadEncryptedEvent(
      canRequestSession: true,
      sessionId: 'abc123',
      senderKey: 'xyz789',
    );
    await tester.pumpWidget(_buildBubble(event: event));
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pump();

    // No exception means the GestureDetector handled the null-safe chain.
    expect(find.text('Retry'), findsOneWidget);
  });
}
