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
import 'space_discovery_server_test.mocks.dart';

class _SpyFakeDataSource extends FakeSpaceDiscoveryDataSource {
  _SpyFakeDataSource({super.failingServers})
      : super(delay: Duration.zero);

  final List<String?> queriedServers = [];
  final List<String?> queriedSinceCursors = [];
  final List<String?> queriedTerms = [];

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) {
    queriedServers.add(server);
    queriedSinceCursors.add(since);
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

  void configureClient({required Uri homeserverUri}) {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.homeserver).thenReturn(homeserverUri);
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
  }

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

  testWidgets('switching to matrix.org queries it and resets cursor + search',
      (tester) async {
    configureClient(homeserverUri: Uri.parse('https://example.org'));
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    expect(ds.queriedServers, [null]);
    expect(find.text('matrix.org'), findsOneWidget);
    expect(find.text('example.org'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'rust');
    await tester.pumpAndSettle();
    expect(ds.queriedTerms.last, 'rust');

    await tester.tap(find.text('matrix.org'));
    await tester.pumpAndSettle();

    expect(ds.queriedServers.last, 'matrix.org');
    expect(ds.queriedSinceCursors.last, isNull);
    expect(ds.queriedTerms.last, isNull);
    expect(
      (tester.widget(find.byType(TextField)) as TextField).controller!.text,
      '',
    );
    expect(find.text('matrix.org Lounge'), findsOneWidget);
  });

  testWidgets('federation failure shows server-named error', (tester) async {
    configureClient(homeserverUri: Uri.parse('https://example.org'));
    final ds = _SpyFakeDataSource(failingServers: const {'matrix.org'});
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.tap(find.text('matrix.org'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('matrix.org'),
      findsWidgets,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('selector hidden when own homeserver is matrix.org',
      (tester) async {
    configureClient(homeserverUri: Uri.parse('https://matrix.org'));
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    expect(find.byType(SegmentedButton<String?>), findsNothing);
    expect(ds.queriedServers, [null]);
  });
}
