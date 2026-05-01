import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'space_discovery_search_test.mocks.dart';

class _SpyFakeDataSource extends FakeSpaceDiscoveryDataSource {
  _SpyFakeDataSource() : super(delay: Duration.zero);

  int queryCallCount = 0;
  final List<String?> queriedTerms = [];

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) {
    queryCallCount++;
    queriedTerms.add(filter?.genericSearchTerm);
    return super.queryPublicRooms(
      limit: limit,
      since: since,
      server: server,
      filter: filter,
    );
  }
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late SelectionService selectionService;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
  });

  Widget buildHarness(SpaceDiscoveryDataSource dataSource) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => SpaceDiscoveryDialog.show(
                context,
                matrixService: mockMatrixService,
                dataSource: dataSource,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('typing filters server-side after debounce', (tester) async {
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    expect(find.text('Linux'), findsOneWidget);
    expect(ds.queryCallCount, 1);
    expect(ds.queriedTerms.last, isNull);

    await tester.enterText(find.byType(TextField), 'rust');
    await tester.pump(const Duration(milliseconds: 100));
    expect(ds.queryCallCount, 1);

    await tester.pumpAndSettle();

    expect(ds.queryCallCount, 2);
    expect(ds.queriedTerms.last, 'rust');
    expect(find.text('Rust'), findsOneWidget);
    expect(find.text('Linux'), findsNothing);
  });

  testWidgets('rapid typing fires only one request', (tester) async {
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    final initialCalls = ds.queryCallCount;

    await tester.enterText(find.byType(TextField), 'r');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'ru');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'rus');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'rust');
    await tester.pump(const Duration(milliseconds: 200));
    expect(ds.queryCallCount - initialCalls, 0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(ds.queryCallCount - initialCalls, 1);
    expect(ds.queriedTerms.last, 'rust');
  });

  testWidgets('clear button restores unfiltered list', (tester) async {
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'rust');
    await tester.pumpAndSettle();
    expect(find.text('Linux'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(ds.queriedTerms.last, isNull);
    expect(find.text('Linux'), findsOneWidget);
  });

  testWidgets('empty result shows query-specific message', (tester) async {
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'zzzzzzz');
    await tester.pumpAndSettle();

    expect(find.text('No spaces match "zzzzzzz".'), findsOneWidget);
  });
}
