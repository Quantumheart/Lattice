import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/media_viewer_shell.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
  MockSpec<User>(),
])
import 'media_viewer_shell_test.mocks.dart';

void main() {
  late MockEvent mockEvent;
  late MockRoom mockRoom;
  late MockClient mockClient;
  late MockUser mockUser;

  setUp(() {
    mockEvent = MockEvent();
    mockRoom = MockRoom();
    mockClient = MockClient();
    mockUser = MockUser();

    when(mockEvent.senderFromMemoryOrFallback).thenReturn(mockUser);
    when(mockEvent.room).thenReturn(mockRoom);
    when(mockEvent.originServerTs).thenReturn(DateTime(2026));
    when(mockEvent.senderId).thenReturn('@alice:example.com');
    when(mockEvent.body).thenReturn('image.png');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockUser.displayName).thenReturn('Alice');
    when(mockUser.avatarUrl).thenReturn(null);
    when(mockUser.id).thenReturn('@alice:example.com');
  });

  Widget buildTestWidget({Widget? child}) {
    return MaterialApp(
      home: Scaffold(
        body: MediaViewerShell(
          event: mockEvent,
          child: child ?? const Placeholder(),
        ),
      ),
    );
  }

  group('MediaViewerShell', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Text('media content')),
      );
      await tester.pump();

      expect(find.text('media content'), findsOneWidget);
    });

    testWidgets('shows sender display name in top bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows close button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('shows download button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    });

    testWidgets('top bar auto-hides after 3 seconds', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));

      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 0.0);
    });

    testWidgets('tapping toggles bar visibility', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));

      final hiddenOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(hiddenOpacity.opacity, 0.0);

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      final visibleOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(visibleOpacity.opacity, 1.0);
    });

    testWidgets('falls back to senderId when displayName is null', (tester) async {
      when(mockUser.displayName).thenReturn(null);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('@alice:example.com'), findsOneWidget);
    });
  });
}
