import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/screens/devices_screen.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
])
import 'devices_screen_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.deviceID).thenReturn('THISDEVICE');
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockMatrix.onUiaRequest).thenAnswer(
      (_) => const Stream<UiaRequest>.empty(),
    );
    when(mockMatrix.chatBackupNeeded).thenReturn(false);
    when(mockClient.userDeviceKeys).thenReturn({});
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrix,
        child: const DevicesScreen(),
      ),
    );
  }

  group('DevicesScreen', () {
    testWidgets('shows loading indicator initially', (tester) async {
      // Never complete the getDevices future.
      when(mockClient.getDevices()).thenAnswer(
        (_) => Completer<List<Device>>().future,
      );

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      when(mockClient.getDevices()).thenThrow(Exception('Network error'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Failed to load devices'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows current device and other devices', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockClient.getDevices()).thenAnswer((_) async => [
            Device(
              deviceId: 'THISDEVICE',
              displayName: 'Lattice Flutter',
              lastSeenTs: now,
            ),
            Device(
              deviceId: 'OTHER1',
              displayName: 'Element Android',
              lastSeenTs: now - 3600000,
            ),
            Device(
              deviceId: 'OTHER2',
              displayName: 'Element Web',
              lastSeenTs: now - 7200000,
            ),
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('THIS DEVICE'), findsOneWidget);
      expect(find.text('OTHER DEVICES'), findsOneWidget);
      expect(find.text('Lattice Flutter'), findsOneWidget);
      expect(find.text('Element Android'), findsOneWidget);
      expect(find.text('Element Web'), findsOneWidget);
      expect(find.text('Remove all other devices'), findsOneWidget);
    });

    testWidgets('shows empty state when no other devices', (tester) async {
      when(mockClient.getDevices()).thenAnswer((_) async => [
            Device(
              deviceId: 'THISDEVICE',
              displayName: 'Lattice Flutter',
            ),
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No other devices found'), findsOneWidget);
      expect(find.text('Remove all other devices'), findsNothing);
    });

    testWidgets('shows backup warning when backup needed', (tester) async {
      when(mockMatrix.chatBackupNeeded).thenReturn(true);
      when(mockClient.getDevices()).thenAnswer((_) async => [
            Device(deviceId: 'THISDEVICE', displayName: 'Lattice Flutter'),
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Chat backup is not set up'),
        findsOneWidget,
      );
    });

    testWidgets('rename device shows dialog and calls updateDevice',
        (tester) async {
      when(mockClient.getDevices()).thenAnswer((_) async => [
            Device(
              deviceId: 'THISDEVICE',
              displayName: 'Lattice Flutter',
            ),
          ]);
      when(mockClient.updateDevice(any, displayName: anyNamed('displayName')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the current device to rename.
      await tester.tap(find.text('Lattice Flutter'));
      await tester.pumpAndSettle();

      expect(find.text('Rename device'), findsOneWidget);

      // Enter new name and submit.
      await tester.enterText(find.byType(TextField), 'My Desktop');
      await tester.tap(find.text('Rename'));
      await tester.pump();

      verify(mockClient.updateDevice('THISDEVICE', displayName: 'My Desktop'))
          .called(1);
    });

    testWidgets('remove device shows confirmation dialog', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      when(mockClient.getDevices()).thenAnswer((_) async => [
            Device(deviceId: 'THISDEVICE', displayName: 'Lattice Flutter'),
            Device(
              deviceId: 'OTHER1',
              displayName: 'Old Phone',
              lastSeenTs: now,
            ),
          ]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Find the popup menu button by icon (the three-dot menu).
      final popupButton = find.byIcon(Icons.more_vert);
      if (popupButton.evaluate().isNotEmpty) {
        await tester.tap(popupButton);
      } else {
        // PopupMenuButton renders as an IconButton with an overflow icon.
        // Find it by widget type within the DeviceListItem for 'Old Phone'.
        await tester.tap(find.byWidgetPredicate(
          (widget) => widget is PopupMenuButton,
        ));
      }
      await tester.pumpAndSettle();

      // Tap remove.
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(find.text('Remove device?'), findsOneWidget);
      expect(find.textContaining('Old Phone'), findsWidgets);
    });

    testWidgets('retry button calls getDevices again', (tester) async {
      when(mockClient.getDevices()).thenThrow(Exception('fail'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Failed to load devices'), findsOneWidget);

      // Verify getDevices was called once for initial load.
      verify(mockClient.getDevices()).called(1);

      // Tap retry — this triggers another getDevices call.
      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(mockClient.getDevices()).called(1);
    });
  });
}
