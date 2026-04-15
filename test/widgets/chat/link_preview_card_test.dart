import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/opengraph_service.dart';
import 'package:kohera/features/chat/widgets/link_preview_card.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<OpenGraphService>()])
import 'link_preview_card_test.mocks.dart';

void main() {
  late MockOpenGraphService mockOgService;

  setUp(() {
    mockOgService = MockOpenGraphService();
  });

  Widget buildTestWidget({
    String url = 'https://example.com/page',
    bool isMe = false,
  }) {
    return Provider<OpenGraphService>.value(
      value: mockOgService,
      child: MaterialApp(
        home: Scaffold(
          body: LinkPreviewCard(url: url, isMe: isMe),
        ),
      ),
    );
  }

  group('LinkPreviewCard', () {
    testWidgets('shows nothing while loading', (tester) async {
      final completer = Completer<OpenGraphData?>();
      when(mockOgService.fetch(any)).thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Example'), findsNothing);

      completer.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('shows nothing when data is null', (tester) async {
      when(mockOgService.fetch(any)).thenAnswer((_) async => null);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Example'), findsNothing);
    });

    testWidgets('shows title and description when data loaded',
        (tester) async {
      when(mockOgService.fetch(any)).thenAnswer(
        (_) async => OpenGraphData(
              url: 'https://example.com/page',
              title: 'My Title',
              description: 'My Description',
            ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('My Title'), findsOneWidget);
      expect(find.text('My Description'), findsOneWidget);
    });

    testWidgets('shows domain when siteName is absent', (tester) async {
      when(mockOgService.fetch(any)).thenAnswer(
        (_) async => OpenGraphData(
              url: 'https://example.com/page',
              title: 'Title',
            ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('shows siteName when present', (tester) async {
      when(mockOgService.fetch(any)).thenAnswer(
        (_) async => OpenGraphData(
              url: 'https://example.com/page',
              title: 'Title',
              siteName: 'Example Site',
            ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Example Site'), findsOneWidget);
    });

    testWidgets('URL change triggers second fetch', (tester) async {
      when(mockOgService.fetch('https://a.com')).thenAnswer(
        (_) async => OpenGraphData(url: 'https://a.com', title: 'A'),
      );
      when(mockOgService.fetch('https://b.com')).thenAnswer(
        (_) async => OpenGraphData(url: 'https://b.com', title: 'B'),
      );

      await tester.pumpWidget(
        Provider<OpenGraphService>.value(
          value: mockOgService,
          child: const MaterialApp(
            home: Scaffold(
              body: LinkPreviewCard(url: 'https://a.com', isMe: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      await tester.pumpWidget(
        Provider<OpenGraphService>.value(
          value: mockOgService,
          child: const MaterialApp(
            home: Scaffold(
              body: LinkPreviewCard(url: 'https://b.com', isMe: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);

      verify(mockOgService.fetch('https://a.com')).called(1);
      verify(mockOgService.fetch('https://b.com')).called(1);
    });
  });
}
