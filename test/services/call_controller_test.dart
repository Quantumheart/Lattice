import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/calling/services/call_controller.dart';

void main() {
  late CallController controller;

  setUp(() {
    controller = CallController(roomId: '!room:test', displayName: 'Test');
  });

  tearDown(() => controller.dispose());

  Future<void> joinController() async {
    await controller.join();
  }

  group('media controls', () {
    test('toggleMic flips isMicMuted and updates local participant', () async {
      await joinController();
      expect(controller.isMicMuted, isFalse);

      controller.toggleMic();
      expect(controller.isMicMuted, isTrue);
      final local = controller.participants.firstWhere((p) => p.isLocal);
      expect(local.isMuted, isTrue);

      controller.toggleMic();
      expect(controller.isMicMuted, isFalse);
      final localAfter = controller.participants.firstWhere((p) => p.isLocal);
      expect(localAfter.isMuted, isFalse);
    });

    test('toggleCamera flips isCameraOff and updates local participant', () async {
      await joinController();
      expect(controller.isCameraOff, isFalse);

      controller.toggleCamera();
      expect(controller.isCameraOff, isTrue);
      final local = controller.participants.firstWhere((p) => p.isLocal);
      expect(local.isAudioOnly, isTrue);

      controller.toggleCamera();
      expect(controller.isCameraOff, isFalse);
      final localAfter = controller.participants.firstWhere((p) => p.isLocal);
      expect(localAfter.isAudioOnly, isFalse);
    });

    test('flipCamera toggles isFrontCamera', () async {
      await joinController();
      expect(controller.isFrontCamera, isTrue);

      controller.flipCamera();
      expect(controller.isFrontCamera, isFalse);

      controller.flipCamera();
      expect(controller.isFrontCamera, isTrue);
    });

    test('toggleScreenShare flips isScreenSharing', () async {
      await joinController();
      expect(controller.isScreenSharing, isFalse);

      controller.toggleScreenShare();
      expect(controller.isScreenSharing, isTrue);

      controller.toggleScreenShare();
      expect(controller.isScreenSharing, isFalse);
    });

    test('toggles do not affect remote participants', () async {
      await joinController();
      final remoteBefore = controller.participants.where((p) => !p.isLocal).toList();

      controller.toggleMic();
      controller.toggleCamera();

      final remoteAfter = controller.participants.where((p) => !p.isLocal).toList();
      expect(remoteAfter.length, remoteBefore.length);
      for (var i = 0; i < remoteBefore.length; i++) {
        expect(remoteAfter[i].isMuted, remoteBefore[i].isMuted);
        expect(remoteAfter[i].isAudioOnly, remoteBefore[i].isAudioOnly);
      }
    });

    test('notifies listeners on each toggle', () async {
      await joinController();
      var count = 0;
      controller.addListener(() => count++);

      controller.toggleMic();
      controller.toggleCamera();
      controller.flipCamera();
      controller.toggleScreenShare();
      expect(count, 4);
    });
  });

  group('hangUp', () {
    test('resets media control state', () async {
      await joinController();
      controller.toggleMic();
      controller.toggleCamera();
      controller.flipCamera();
      controller.toggleScreenShare();

      controller.hangUp();

      expect(controller.isMicMuted, isFalse);
      expect(controller.isCameraOff, isFalse);
      expect(controller.isFrontCamera, isTrue);
      expect(controller.isScreenSharing, isFalse);
    });

    test('clears participants and sets ended state', () async {
      await joinController();
      expect(controller.participants, isNotEmpty);

      controller.hangUp();

      expect(controller.participants, isEmpty);
      expect(controller.state, CallState.ended);
    });
  });

  group('elapsed timer', () {
    test('increments elapsed after connected', () {
      fakeAsync((async) {
        unawaited(controller.join());
        async.elapse(const Duration(milliseconds: 500));
        expect(controller.state, CallState.connected);

        async.elapse(const Duration(seconds: 3));
        expect(controller.elapsed.inSeconds, 3);

        controller.hangUp();
      });
    });

    test('stops timer on hangUp', () {
      fakeAsync((async) {
        unawaited(controller.join());
        async.elapse(const Duration(milliseconds: 500));

        async.elapse(const Duration(seconds: 2));
        controller.hangUp();

        final elapsed = controller.elapsed;
        async.elapse(const Duration(seconds: 5));
        expect(controller.elapsed, elapsed);
      });
    });
  });
}
