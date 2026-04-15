import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/rooms/widgets/message_search_tiles.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';

void main() {
  String? lastNavigatedRoom;

  Widget buildTestWidget({required Widget child}) {
    lastNavigatedRoom = null;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: 'rooms/:roomId',
              name: Routes.room,
              builder: (context, state) {
                lastNavigatedRoom = state.pathParameters['roomId'];
                return Scaffold(
                  body: Text('Room ${state.pathParameters['roomId']}'),
                );
              },
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(routerConfig: router);
  }

  // ── MessageSearchHeader ─────────────────────────────────────

  group('MessageSearchHeader', () {
    testWidgets('shows "MESSAGES" when resultCount is null', (tester) async {
      final item = MessageSearchHeaderItem(isLoading: false);

      await tester.pumpWidget(
        buildTestWidget(child: MessageSearchHeader(item: item)),
      );

      expect(find.text('MESSAGES'), findsOneWidget);
    });

    testWidgets('shows "MESSAGES (5)" when resultCount is 5', (tester) async {
      final item = MessageSearchHeaderItem(isLoading: false, resultCount: 5);

      await tester.pumpWidget(
        buildTestWidget(child: MessageSearchHeader(item: item)),
      );

      expect(find.text('MESSAGES (5)'), findsOneWidget);
    });

    testWidgets('shows spinner when loading', (tester) async {
      final item = MessageSearchHeaderItem(isLoading: true);

      await tester.pumpWidget(
        buildTestWidget(child: MessageSearchHeader(item: item)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides spinner when not loading', (tester) async {
      final item = MessageSearchHeaderItem(isLoading: false);

      await tester.pumpWidget(
        buildTestWidget(child: MessageSearchHeader(item: item)),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error text when error is set', (tester) async {
      final item = MessageSearchHeaderItem(
        isLoading: false,
        error: 'Search failed',
      );

      await tester.pumpWidget(
        buildTestWidget(child: MessageSearchHeader(item: item)),
      );

      expect(find.text('Search failed'), findsOneWidget);
    });
  });

  // ── MessageSearchResultTile ──────────────────────────────────

  group('MessageSearchResultTile', () {
    MessageSearchResult makeResult({
      String roomId = '!room:example.com',
      String roomName = 'Test Room',
      String senderName = 'Alice',
      String body = 'Hello world',
    }) {
      return MessageSearchResult(
        roomId: roomId,
        roomName: roomName,
        senderName: senderName,
        senderId: '@alice:example.com',
        body: body,
        eventId: r'$evt1',
        originServerTs: DateTime.now(),
      );
    }

    testWidgets('renders room name, sender, and body', (tester) async {
      final result = makeResult();

      await tester.pumpWidget(
        buildTestWidget(
          child: MessageSearchResultTile(result: result, query: 'hello'),
        ),
      );

      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('highlighted text has bold weight', (tester) async {
      final result = makeResult(body: 'Say hello to you');

      await tester.pumpWidget(
        buildTestWidget(
          child: MessageSearchResultTile(result: result, query: 'hello'),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText).last);
      final textSpan = richText.text as TextSpan;
      final matchSpan = textSpan.children!
          .cast<TextSpan>()
          .firstWhere((s) => s.text?.toLowerCase() == 'hello');
      expect(matchSpan.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('tap navigates to room', (tester) async {
      final result = makeResult(roomId: '!nav:example.com');

      await tester.pumpWidget(
        buildTestWidget(
          child: MessageSearchResultTile(result: result, query: 'hello'),
        ),
      );

      await tester.tap(find.text('Test Room'));
      await tester.pumpAndSettle();

      expect(lastNavigatedRoom, '!nav:example.com');
    });
  });

  // ── LoadMoreButton ───────────────────────────────────────────

  group('LoadMoreButton', () {
    testWidgets('shows button text when not loading', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: LoadMoreButton(isLoading: false, onPressed: () {}),
        ),
      );

      expect(find.text('Load more messages'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows spinner when loading', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: LoadMoreButton(isLoading: true, onPressed: () {}),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Load more messages'), findsNothing);
    });

    testWidgets('tap fires callback', (tester) async {
      var pressed = false;

      await tester.pumpWidget(
        buildTestWidget(
          child: LoadMoreButton(
            isLoading: false,
            onPressed: () => pressed = true,
          ),
        ),
      );

      await tester.tap(find.text('Load more messages'));
      expect(pressed, isTrue);
    });
  });
}
