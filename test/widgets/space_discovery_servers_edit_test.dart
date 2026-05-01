import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/spaces/services/space_discovery_data_source.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'space_discovery_servers_edit_test.mocks.dart';

class _SpyFakeDataSource extends FakeSpaceDiscoveryDataSource {
  _SpyFakeDataSource() : super(delay: Duration.zero);

  final List<String?> queriedServers = [];

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    int? limit,
    String? since,
    String? server,
    PublicRoomQueryFilter? filter,
  }) {
    queriedServers.add(server);
    return super.queryPublicRooms(
      limit: limit,
      since: since,
      server: server,
      filter: filter,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late SelectionService selectionService;
  late PreferencesService prefsService;

  Future<void> configure() async {
    SharedPreferences.setMockInitialValues({});
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.homeserver)
        .thenReturn(Uri.parse('https://example.org'));
    selectionService = SelectionService(client: mockClient);
    when(mockMatrixService.selection).thenReturn(selectionService);
    prefsService = PreferencesService();
    await prefsService.init();
  }

  Widget buildHarness(SpaceDiscoveryDataSource dataSource) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MatrixService>.value(value: mockMatrixService),
        ChangeNotifierProvider<SelectionService>.value(value: selectionService),
        ChangeNotifierProvider<PreferencesService>.value(value: prefsService),
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

  testWidgets('add valid host: chip + prefs updated + query fires',
      (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'matrix.example.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(prefsService.browseServers, contains('matrix.example.org'));
    expect(
      find.widgetWithText(InputChip, 'matrix.example.org'),
      findsOneWidget,
    );
    expect(ds.queriedServers.last, 'matrix.example.org');
  });

  testWidgets('invalid host shows inline error and does not save',
      (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    final before = List<String>.from(prefsService.browseServers);

    await tester.tap(find.widgetWithText(ActionChip, 'Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'http://x');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Hostname only (no scheme or path).'), findsOneWidget);
    expect(prefsService.browseServers, before);
  });

  testWidgets('remove non-default after confirm; selected falls back',
      (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    // Select matrix.org first.
    await tester.tap(find.widgetWithText(InputChip, 'matrix.org'));
    await tester.pumpAndSettle();
    expect(ds.queriedServers.last, 'matrix.org');

    // Tap delete on the matrix.org chip.
    await tester.tap(find.byTooltip('Remove matrix.org'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(prefsService.browseServers, isNot(contains('matrix.org')));
    expect(find.widgetWithText(InputChip, 'matrix.org'), findsNothing);
    // Selection fell back to own server (null).
    expect(ds.queriedServers.last, isNull);
  });

  testWidgets('own homeserver chip has no delete icon', (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    expect(find.byTooltip('Remove example.org'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'example.org'), findsOneWidget);
  });

  testWidgets('rejects duplicate of existing server', (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'matrix.org');
    await tester.pumpAndSettle();

    expect(find.text('Server already added.'), findsOneWidget);
  });

  testWidgets('rejects own homeserver as duplicate', (tester) async {
    await configure();
    final ds = _SpyFakeDataSource();
    await tester.pumpWidget(buildHarness(ds));
    await openDialog(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Add server'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'example.org');
    await tester.pumpAndSettle();

    expect(find.text('This is already your homeserver.'), findsOneWidget);
  });
}
