import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/pulsing_avatar.dart';

void main() {
  Widget buildTestWidget({
    String displayName = 'Alice',
    double radius = 48,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PulsingAvatar(displayName: displayName, radius: radius),
      ),
    );
  }

  group('PulsingAvatar', () {
    testWidgets('shows first character of displayName uppercased', (tester) async {
      await tester.pumpWidget(buildTestWidget(displayName: 'bob'));
      await tester.pump();

      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('shows ? for empty displayName', (tester) async {
      await tester.pumpWidget(buildTestWidget(displayName: ''));
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders CircleAvatar with specified radius', (tester) async {
      await tester.pumpWidget(buildTestWidget(radius: 64));
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 64);
    });

    testWidgets('uses ScaleTransition for animation', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(ScaleTransition), findsWidgets);
    });

    testWidgets('disposes animation controller cleanly', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
    });
  });
}
