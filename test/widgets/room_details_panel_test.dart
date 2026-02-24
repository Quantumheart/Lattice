import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/room_details_panel.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
])
import 'room_details_panel_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockRoom;
  late CachedStreamController<SyncUpdate> syncController;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockRoom = MockRoom();
    syncController = CachedStreamController<SyncUpdate>();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});
    when(mockClient.onSync).thenReturn(syncController);
    when(mockClient.userDeviceKeys).thenReturn({});
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.topic).thenReturn('A test topic');
    when(mockRoom.encrypted).thenReturn(false);
    when(mockRoom.isDirectChat).thenReturn(false);
    when(mockRoom.isFavourite).thenReturn(false);
    when(mockRoom.pushRuleState).thenReturn(PushRuleState.notify);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 3,
      'm.invited_member_count': 0,
    }));
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.canChangeStateEvent(any)).thenReturn(false);
    when(mockRoom.canChangePowerLevel).thenReturn(false);
    when(mockRoom.canKick).thenReturn(false);
    when(mockRoom.canBan).thenReturn(false);
    when(mockRoom.requestParticipants(any)).thenAnswer((_) async => []);
  });

  Widget buildTestWidget({bool isFullPage = false}) {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrixService,
        child: Scaffold(
          body: RoomDetailsPanel(
            roomId: '!room:example.com',
            isFullPage: isFullPage,
          ),
        ),
      ),
    );
  }

  group('RoomDetailsPanel', () {
    testWidgets('shows room name and topic', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Test Room'), findsWidgets);
      expect(find.text('A test topic'), findsOneWidget);
    });

    testWidgets('shows member count', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('3 members'), findsOneWidget);
    });

    testWidgets('shows "Room not found" for missing room', (tester) async {
      when(mockClient.getRoomById('!room:example.com')).thenReturn(null);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Room not found'), findsOneWidget);
    });

    testWidgets('shows encryption status for unencrypted room', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Not encrypted'), findsOneWidget);
    });

    testWidgets('shows encryption status for encrypted room', (tester) async {
      when(mockRoom.encrypted).thenReturn(true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Encrypted'), findsOneWidget);
    });

    testWidgets('shows Mute/Star/Invite/Leave actions', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('toggles mute', (tester) async {
      when(mockRoom.setPushRuleState(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mute'));
      await tester.pumpAndSettle();

      verify(mockRoom.setPushRuleState(PushRuleState.dontNotify)).called(1);
    });

    testWidgets('toggles favourite', (tester) async {
      when(mockRoom.setFavourite(any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Star'));
      await tester.pumpAndSettle();

      verify(mockRoom.setFavourite(true)).called(1);
    });

    testWidgets('leave shows confirmation dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Leave room?'), findsOneWidget);
      expect(find.text('You will leave "Test Room".'), findsOneWidget);
    });

    testWidgets('leave confirmation calls room.leave', (tester) async {
      when(mockRoom.leave()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      // Tap the 'Leave' button inside the confirmation dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      verify(mockRoom.leave()).called(1);
      verify(mockMatrixService.selectRoom(null)).called(1);
    });

    testWidgets('notification section shows radio options', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('All messages'), findsOneWidget);
      expect(find.text('Mentions only'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
    });

    testWidgets('renders as Scaffold when isFullPage is true', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<MatrixService>.value(
          value: mockMatrixService,
          child: const RoomDetailsPanel(
            roomId: '!room:example.com',
            isFullPage: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // AppBar should show the room name
      expect(find.widgetWithText(AppBar, 'Test Room'), findsOneWidget);
    });

    testWidgets('encrypted DM shows device verification summary', (tester) async {
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.isDirectChat).thenReturn(true);
      when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

      final bobKeys = DeviceKeysList('@bob:example.com', mockClient);
      bobKeys.deviceKeys['DEVICE1'] = DeviceKeys.fromJson({
        'user_id': '@bob:example.com',
        'device_id': 'DEVICE1',
        'algorithms': ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
        'keys': {
          'curve25519:DEVICE1': 'fakekey1',
          'ed25519:DEVICE1': 'fakekey2',
        },
      }, mockClient);
      bobKeys.deviceKeys['DEVICE2'] = DeviceKeys.fromJson({
        'user_id': '@bob:example.com',
        'device_id': 'DEVICE2',
        'algorithms': ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
        'keys': {
          'curve25519:DEVICE2': 'fakekey3',
          'ed25519:DEVICE2': 'fakekey4',
        },
      }, mockClient);

      when(mockClient.userDeviceKeys).thenReturn({
        '@bob:example.com': bobKeys,
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Encrypted'), findsOneWidget);
      expect(find.textContaining('of 2 devices verified'), findsOneWidget);
    });

    testWidgets('encrypted non-DM room does not show device verification', (tester) async {
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.isDirectChat).thenReturn(false);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Encrypted'), findsOneWidget);
      expect(find.textContaining('devices verified'), findsNothing);
    });

    testWidgets('DM device list expands on tap', (tester) async {
      when(mockRoom.encrypted).thenReturn(true);
      when(mockRoom.isDirectChat).thenReturn(true);
      when(mockRoom.directChatMatrixID).thenReturn('@bob:example.com');

      final bobKeys = DeviceKeysList('@bob:example.com', mockClient);
      bobKeys.deviceKeys['DEVICE1'] = DeviceKeys.fromJson({
        'user_id': '@bob:example.com',
        'device_id': 'DEVICE1',
        'algorithms': ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2'],
        'keys': {
          'curve25519:DEVICE1': 'fakekey1',
          'ed25519:DEVICE1': 'fakekey2',
        },
      }, mockClient);

      when(mockClient.userDeviceKeys).thenReturn({
        '@bob:example.com': bobKeys,
      });

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Device list should not be visible initially
      expect(find.text('DEVICE1'), findsNothing);

      // Tap the verification summary to expand
      await tester.tap(find.textContaining('of 1 device verified'));
      await tester.pumpAndSettle();

      // Device should now be visible
      expect(find.text('DEVICE1'), findsOneWidget);
    });
  });
}
