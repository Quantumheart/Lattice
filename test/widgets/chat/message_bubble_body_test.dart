import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/verification_request_tile.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import 'message_bubble_body_test.mocks.dart';

late MockRoom _mockRoom;
late MockClient _mockClient;

MockEvent _makeEvent({
  String msgtype = MessageTypes.Text,
  String body = 'hello',
  String senderId = '@alice:example.com',
  String senderDisplayName = 'Alice',
  bool redacted = false,
  String? formattedText,
  Map<String, Object?>? content,
  String? redactorId,
  String? redactorDisplayName,
}) {
  final event = MockEvent();
  when(event.senderId).thenReturn(senderId);
  when(event.body).thenReturn(body);
  when(event.messageType).thenReturn(msgtype);
  when(event.redacted).thenReturn(redacted);
  when(event.formattedText).thenReturn(formattedText ?? '');
  when(event.content).thenReturn(
    content ??
        <String, Object?>{
          'body': body,
          'msgtype': msgtype,
          if (formattedText != null) ...{
            'format': 'org.matrix.custom.html',
            'formatted_body': formattedText,
          },
        },
  );
  when(event.room).thenReturn(_mockRoom);

  final sender = MockUser();
  when(sender.displayName).thenReturn(senderDisplayName);
  when(sender.calcDisplayname()).thenReturn(senderDisplayName);
  when(sender.avatarUrl).thenReturn(null);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);

  if (redacted && redactorId != null) {
    final redactedEvent = MockEvent();
    when(redactedEvent.senderId).thenReturn(redactorId);
    when(event.redactedBecause).thenReturn(redactedEvent);
    final redactorUser = MockUser();
    when(redactorUser.displayName).thenReturn(redactorDisplayName);
    when(_mockRoom.unsafeGetUserFromMemoryOrFallback(redactorId))
        .thenReturn(redactorUser);
  } else {
    when(event.redactedBecause).thenReturn(null);
  }

  return event;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

Widget _buildBody(MockEvent event, {bool isMe = false}) {
  return _wrap(
    MessageBubbleBody(
      event: event,
      displayEvent: event,
      bodyText: event.body,
      isMe: isMe,
      metrics: DensityMetrics.of(MessageDensity.defaultDensity),
    ),
  );
}

void main() {
  setUp(() {
    _mockRoom = MockRoom();
    _mockClient = MockClient();
    when(_mockRoom.client).thenReturn(_mockClient);
  });

  group('MessageBubbleBody — text dispatch', () {
    testWidgets('plain text renders LinkableText with body', (tester) async {
      final event = _makeEvent(body: 'hello world');
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('notice renders as LinkableText', (tester) async {
      final event = _makeEvent(msgtype: MessageTypes.Notice, body: 'notice');
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(LinkableText), findsOneWidget);
    });
  });

  group('MessageBubbleBody — emote', () {
    testWidgets('emote prefixes "* Sender " before body', (tester) async {
      final event = _makeEvent(
        msgtype: MessageTypes.Emote,
        body: 'waves',
        senderDisplayName: 'Alice',
      );
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(LinkableText), findsOneWidget);
      expect(find.text('* Alice waves'), findsOneWidget);
    });

    testWidgets('emote with HTML uses HtmlMessageText and escapes sender name',
        (tester) async {
      final event = _makeEvent(
        msgtype: MessageTypes.Emote,
        body: 'waves',
        senderDisplayName: '<script>evil</script>',
        formattedText: '<em>waves</em>',
      );
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(HtmlMessageText), findsOneWidget);
      final html = tester.widget<HtmlMessageText>(find.byType(HtmlMessageText));
      expect(html.html, contains('&lt;script&gt;evil&lt;/script&gt;'));
      expect(html.html, isNot(contains('<script>evil</script>')));
    });
  });

  group('MessageBubbleBody — server notice', () {
    testWidgets('wraps content with campaign icon', (tester) async {
      final event = _makeEvent(msgtype: 'm.server_notice', body: 'notice');
      await tester.pumpWidget(_buildBody(event));

      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
      expect(find.text('notice'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — redacted', () {
    testWidgets('isMe shows "You deleted this message"', (tester) async {
      final event = _makeEvent(redacted: true);
      await tester.pumpWidget(_buildBody(event, isMe: true));

      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('other sender shows "This message was deleted"',
        (tester) async {
      final event = _makeEvent(redacted: true);
      await tester.pumpWidget(_buildBody(event));

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('moderator redact shows "Deleted by <name>"', (tester) async {
      final event = _makeEvent(
        redacted: true,
        senderId: '@alice:x',
        redactorId: '@bob:x',
        redactorDisplayName: 'Bob',
      );
      await tester.pumpWidget(_buildBody(event));

      expect(find.text('Deleted by Bob'), findsOneWidget);
    });

    testWidgets('self-redact shows generic message', (tester) async {
      final event = _makeEvent(
        redacted: true,
        senderId: '@alice:x',
        redactorId: '@alice:x',
      );
      await tester.pumpWidget(_buildBody(event));

      expect(find.text('This message was deleted'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — bad encrypted', () {
    testWidgets('shows lock icon and fallback text', (tester) async {
      final event = _makeEvent(msgtype: MessageTypes.BadEncrypted);
      await tester.pumpWidget(_buildBody(event));

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Unable to decrypt this message'), findsOneWidget);
    });
  });

  group('MessageBubbleBody — verification request', () {
    testWidgets('renders VerificationRequestTile', (tester) async {
      final event = _makeEvent(msgtype: EventTypes.KeyVerificationRequest);
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(VerificationRequestTile), findsOneWidget);
    });
  });

  group('MessageBubbleBody — html body', () {
    testWidgets('non-emote html renders HtmlMessageText without prefix',
        (tester) async {
      final event = _makeEvent(
        body: 'hello',
        formattedText: '<b>hello</b>',
      );
      await tester.pumpWidget(_buildBody(event));

      expect(find.byType(HtmlMessageText), findsOneWidget);
      final html = tester.widget<HtmlMessageText>(find.byType(HtmlMessageText));
      expect(html.html, '<b>hello</b>');
    });
  });
}
