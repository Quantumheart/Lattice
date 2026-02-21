import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/screens/chat_screen.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])
import 'chat_search_test.mocks.dart';

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

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockTimeline.events).thenReturn([]);
    when(mockTimeline.canRequestHistory).thenReturn(false);
    when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
        .thenAnswer((_) async => mockTimeline);
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrix),
        ChangeNotifierProvider<PreferencesService>.value(value: prefsService),
      ],
      child: const MaterialApp(
        home: ChatScreen(roomId: '!room:example.com'),
      ),
    );
  }

  group('ChatScreen search', () {
    testWidgets('shows search icon in app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('tapping search icon shows search app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Search text field should appear.
      expect(find.widgetWithText(TextField, ''), findsWidgets);
      // Back arrow should be present.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      // The original room title should be gone.
      expect(find.text('Test Room'), findsNothing);
      // Hint text should show.
      expect(find.text('Search messages…'), findsOneWidget);
    });

    testWidgets('shows minimum character hint when query too short',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type less than 3 characters.
      await tester.enterText(find.byType(TextField).last, 'ab');
      await tester.pumpAndSettle();

      expect(
        find.text('Type at least 3 characters to search'),
        findsOneWidget,
      );
    });

    testWidgets('close button clears search and restores app bar',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Tap back to close.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Room name should be back.
      expect(find.text('Test Room'), findsOneWidget);
      // Search hint should be gone.
      expect(find.text('Search messages…'), findsNothing);
    });

    testWidgets('shows empty state when no results found', (tester) async {
      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) async => (
            events: <Event>[],
            nextBatch: null,
            searchedUntil: null,
          ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'xyz123');
      await tester.pump(const Duration(milliseconds: 600)); // debounce
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No messages found'),
        findsOneWidget,
      );
    });

    testWidgets('shows error state when search fails', (tester) async {
      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      )).thenThrow(Exception('Server error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'hello world');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Search failed. Please try again.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('shows loading indicator while searching', (tester) async {
      final completer = Completer<
          ({List<Event> events, String? nextBatch, DateTime? searchedUntil})>();
      when(mockRoom.searchEvents(
        searchTerm: anyNamed('searchTerm'),
        limit: anyNamed('limit'),
        nextBatch: anyNamed('nextBatch'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Open search.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Type a query.
      await tester.enterText(find.byType(TextField).last, 'hello');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(); // Trigger the search.

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future to avoid pending timers.
      completer.complete((
        events: <Event>[],
        nextBatch: null,
        searchedUntil: null,
      ));
      await tester.pumpAndSettle();
    });
  });
}
