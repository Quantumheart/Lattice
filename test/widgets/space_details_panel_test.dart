import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/spaces/widgets/space_details_panel.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'space_details_panel_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockSpace;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockSpace = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!space:example.com')).thenReturn(mockSpace);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockSpace.id).thenReturn('!space:example.com');
    when(mockSpace.getLocalizedDisplayname()).thenReturn('Test Space');
    when(mockSpace.topic).thenReturn('A test topic');
    when(mockSpace.isSpace).thenReturn(true);
    when(mockSpace.client).thenReturn(mockClient);
    when(mockSpace.avatar).thenReturn(null);
    when(mockSpace.canInvite).thenReturn(true);
    when(mockSpace.canChangeStateEvent(any)).thenReturn(false);
    when(mockSpace.canChangePowerLevel).thenReturn(false);
    when(mockSpace.canKick).thenReturn(false);
    when(mockSpace.canBan).thenReturn(false);
    when(mockSpace.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 5,
      'm.invited_member_count': 0,
    }),);
    when(mockSpace.requestParticipants(any)).thenAnswer((_) async => []);
  });

  Widget buildTestWidget({bool isFullPage = false}) {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrixService,
        child: Scaffold(
          body: SpaceDetailsPanel(
            spaceId: '!space:example.com',
            isFullPage: isFullPage,
          ),
        ),
      ),
    );
  }

  group('SpaceDetailsPanel', () {
    testWidgets('shows space name and topic', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Test Space'), findsWidgets);
      expect(find.text('A test topic'), findsOneWidget);
    });

    testWidgets('shows member count', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('5 members'), findsOneWidget);
    });

    testWidgets('shows "Space not found" for missing space', (tester) async {
      when(mockClient.getRoomById('!space:example.com')).thenReturn(null);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Space not found'), findsOneWidget);
    });

    testWidgets('shows Invite and Leave actions', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('hides Invite when user cannot invite', (tester) async {
      when(mockSpace.canInvite).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Invite'), findsNothing);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('renders as Scaffold when isFullPage is true', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<MatrixService>.value(
          value: mockMatrixService,
          child: const SpaceDetailsPanel(
            spaceId: '!space:example.com',
            isFullPage: true,
          ),
        ),
      ),);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Test Space'), findsOneWidget);
    });

    testWidgets('shows admin settings when user has permissions', (tester) async {
      when(mockSpace.canChangeStateEvent(EventTypes.RoomName)).thenReturn(true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('ADMIN SETTINGS'), findsOneWidget);
    });

    testWidgets('hides admin settings when user lacks permissions', (tester) async {
      when(mockSpace.canChangeStateEvent(any)).thenReturn(false);
      when(mockSpace.canChangePowerLevel).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('ADMIN SETTINGS'), findsNothing);
    });

    testWidgets('shows MEMBERS section', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('MEMBERS'), findsOneWidget);
    });

    testWidgets('leave shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Leave space?'), findsOneWidget);
      expect(find.text('You will leave "Test Space".'), findsOneWidget);
    });
  });
}
