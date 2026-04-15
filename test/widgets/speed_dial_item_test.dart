import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/speed_dial_item.dart';

void main() {
  Widget buildTestWidget({
    required VoidCallback onTap,
    String label = 'New Room',
    IconData icon = Icons.add,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SpeedDialItem(label: label, icon: icon, onTap: onTap),
      ),
    );
  }

  group('SpeedDialItem', () {
    testWidgets('displays label text and icon', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          label: 'New Chat',
          icon: Icons.chat,
          onTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Chat'), findsOneWidget);
      expect(find.byIcon(Icons.chat), findsOneWidget);
    });

    testWidgets('calls onTap callback when FAB is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildTestWidget(onTap: () => tapped = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      expect(tapped, isTrue);
    });

    testWidgets('renders FloatingActionButton.small', (tester) async {
      await tester.pumpWidget(buildTestWidget(onTap: () {}));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('label wrapped in Material with elevation', (tester) async {
      await tester.pumpWidget(buildTestWidget(onTap: () {}));
      await tester.pumpAndSettle();

      final materials = tester.widgetList<Material>(find.byType(Material));
      final labelMaterial = materials.firstWhere(
        (m) => m.elevation == 2,
        orElse: () => throw StateError('No Material with elevation 2 found'),
      );
      expect(labelMaterial.borderRadius, BorderRadius.circular(8));
    });
  });
}
