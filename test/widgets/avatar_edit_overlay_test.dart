import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/avatar_edit_overlay.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<Client>()])
import 'avatar_edit_overlay_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
  });

  Widget buildTestWidget({double size = 72}) {
    return MaterialApp(
      home: Scaffold(
        body: AvatarEditOverlay(room: mockRoom, size: size),
      ),
    );
  }

  group('AvatarEditOverlay', () {
    testWidgets('renders plain RoomAvatarWidget when user lacks permission', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar)).thenReturn(false);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(RoomAvatarWidget), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('shows edit overlay when user has permission', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar)).thenReturn(true);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(RoomAvatarWidget), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('shows remove badge when avatar exists', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar)).thenReturn(true);
      when(mockRoom.avatar).thenReturn(Uri.parse('mxc://example.com/avatar'));
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('hides remove badge when no avatar', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar)).thenReturn(true);
      when(mockRoom.avatar).thenReturn(null);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('calls room.setAvatar(null) on remove tap', (tester) async {
      when(mockRoom.canChangeStateEvent(EventTypes.RoomAvatar)).thenReturn(true);
      when(mockRoom.avatar).thenReturn(Uri.parse('mxc://example.com/avatar'));
      when(mockRoom.setAvatar(null)).thenAnswer((_) async => '');
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      verify(mockRoom.setAvatar(null)).called(1);
    });
  });
}
