import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/widgets/voice_banner.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'room_tile_test.mocks.dart';

void main() {
  late MockCallService mockCallService;
  late MockClient mockClient;
  late MockRoom mockRoom;

  setUp(() {
    mockCallService = MockCallService();
    mockClient = MockClient();
    mockRoom = MockRoom();

    when(mockCallService.client).thenReturn(mockClient);
    when(mockCallService.callState).thenReturn(LatticeCallState.idle);
    when(mockCallService.activeCallRoomId).thenReturn(null);
  });

  Widget buildTestWidget({String? currentViewingRoomId}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: VoiceBanner(currentViewingRoomId: currentViewingRoomId),
          ),
        ),
      ],
    );

    return ChangeNotifierProvider<CallService>.value(
      value: mockCallService,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  group('VoiceBanner', () {
    testWidgets('hidden when user is not in a call', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('hidden when user is viewing the same room as active call',
        (tester) async {
      when(mockCallService.callState).thenReturn(LatticeCallState.connected);
      when(mockCallService.activeCallRoomId).thenReturn('!room:example.com');

      await tester.pumpWidget(
        buildTestWidget(currentViewingRoomId: '!room:example.com'),
      );
      await tester.pump();

      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('visible when user is in call but viewing different room',
        (tester) async {
      when(mockCallService.callState).thenReturn(LatticeCallState.connected);
      when(mockCallService.activeCallRoomId).thenReturn('!call-room:example.com');
      when(mockCallService.callElapsed)
          .thenReturn(const Duration(minutes: 1, seconds: 30));
      when(mockClient.getRoomById('!call-room:example.com'))
          .thenReturn(mockRoom);
      when(mockRoom.getLocalizedDisplayname()).thenReturn('Call Room');

      await tester.pumpWidget(
        buildTestWidget(currentViewingRoomId: '!other:example.com'),
      );
      await tester.pump();

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.textContaining('Call Room'), findsOneWidget);
      expect(find.textContaining('01:30'), findsOneWidget);
    });
  });
}
