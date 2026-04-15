import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/section_header.dart';

void main() {
  Widget buildTestWidget(String label) {
    return MaterialApp(
      home: Scaffold(
        body: SectionHeader(label: label),
      ),
    );
  }

  group('SectionHeader', () {
    testWidgets('renders the label text', (tester) async {
      await tester.pumpWidget(buildTestWidget('Members'));
      await tester.pumpAndSettle();

      expect(find.text('Members'), findsOneWidget);
    });

    testWidgets('has correct padding', (tester) async {
      await tester.pumpWidget(buildTestWidget('Settings'));
      await tester.pumpAndSettle();

      final padding = tester.widget<Padding>(find.byType(Padding).first);
      expect(padding.padding, const EdgeInsets.only(left: 4, bottom: 8));
    });

    testWidgets('uses theme primary color', (tester) async {
      const primaryColor = Color(0xFF1234AB);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.light(primary: primaryColor),
          ),
          home: const Scaffold(
            body: SectionHeader(label: 'Test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Test'));
      expect(text.style?.color, primaryColor);
    });
  });
}
