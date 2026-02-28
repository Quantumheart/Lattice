import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/account_switcher.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Client>(),
])
import 'account_switcher_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────

MockMatrixService _makeService(String userId) {
  final service = MockMatrixService();
  final client = MockClient();
  when(service.client).thenReturn(client);
  when(client.userID).thenReturn(userId);
  return service;
}

Widget _buildWidget({
  required List<MatrixService> services,
  required int activeIndex,
  ValueChanged<int>? onAccountTapped,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AccountSwitcher(
        services: services,
        activeIndex: activeIndex,
        onAccountTapped: onAccountTapped ?? (_) {},
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────

void main() {
  late MockMatrixService service1;
  late MockMatrixService service2;

  setUp(() {
    service1 = _makeService('@alice:example.com');
    service2 = _makeService('@bob:example.com');
  });

  testWidgets('displays all accounts', (tester) async {
    await tester.pumpWidget(_buildWidget(
      services: [service1, service2],
      activeIndex: 0,
    ));

    expect(find.text('@alice:example.com'), findsOneWidget);
    expect(find.text('@bob:example.com'), findsOneWidget);
  });

  testWidgets('shows check icon only on active account', (tester) async {
    await tester.pumpWidget(_buildWidget(
      services: [service1, service2],
      activeIndex: 0,
    ));

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('shows ACCOUNTS section header', (tester) async {
    await tester.pumpWidget(_buildWidget(
      services: [service1, service2],
      activeIndex: 0,
    ));

    expect(find.text('ACCOUNTS'), findsOneWidget);
  });

  testWidgets('tapping non-active account calls onAccountTapped with index',
      (tester) async {
    int? tappedIndex;
    await tester.pumpWidget(_buildWidget(
      services: [service1, service2],
      activeIndex: 0,
      onAccountTapped: (i) => tappedIndex = i,
    ));

    await tester.tap(find.text('@bob:example.com'));
    expect(tappedIndex, 1);
  });

  testWidgets('active account name has bold font weight', (tester) async {
    await tester.pumpWidget(_buildWidget(
      services: [service1, service2],
      activeIndex: 0,
    ));

    final aliceText = tester.widget<Text>(find.text('@alice:example.com'));
    expect(aliceText.style?.fontWeight, FontWeight.w600);

    final bobText = tester.widget<Text>(find.text('@bob:example.com'));
    expect(bobText.style?.fontWeight, isNot(FontWeight.w600));
  });
}
