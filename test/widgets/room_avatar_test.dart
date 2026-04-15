import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<Client>()])
import 'room_avatar_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.avatar).thenReturn(null);
    when(mockRoom.getLocalizedDisplayname()).thenReturn('General');
  });

  Widget buildTestWidget({double size = 44}) {
    return MaterialApp(
      home: Scaffold(
        body: RoomAvatarWidget(room: mockRoom, size: size),
      ),
    );
  }

  group('RoomAvatarWidget', () {
    testWidgets('shows initial from room display name', (tester) async {
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Random');
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('shows # when name is empty', (tester) async {
      when(mockRoom.getLocalizedDisplayname()).thenReturn('');
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('#'), findsOneWidget);
    });

    testWidgets('renders at correct size via SizedBox', (tester) async {
      await tester.pumpWidget(buildTestWidget(size: 64));
      await tester.pump();

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 64);
      expect(sizedBox.height, 64);
    });

    testWidgets('uses ClipRRect for rounded rectangle shape', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('border radius is size * 0.28', (tester) async {
      await tester.pumpWidget(buildTestWidget(size: 50));
      await tester.pump();

      final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(
        clipRRect.borderRadius,
        BorderRadius.circular(50 * 0.28),
      );
    });

    testWidgets('shows fallback while avatar is null', (tester) async {
      when(mockRoom.avatar).thenReturn(null);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('G'), findsOneWidget);
    });
  });
}
