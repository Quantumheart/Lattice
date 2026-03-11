import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart';
import 'package:lattice/features/calling/services/call_ringing_service.dart';

import 'call_test_helpers.dart';

void main() {
  late CallRingingService service;
  late FakeRingtoneService fakeRingtone;

  setUp(() {
    fakeRingtone = FakeRingtoneService();
    service = CallRingingService(ringtoneService: fakeRingtone);
  });

  tearDown(() {
    service.dispose();
  });

  IncomingCallInfo _makeInfo({String roomId = '!r:x', String name = 'Alice'}) =>
      IncomingCallInfo(roomId: roomId, callerName: name, callId: 'c1');

  // ── pushIncomingCall ────────────────────────────────────────

  group('pushIncomingCall', () {
    test('stores info and emits on stream', () async {
      final info = _makeInfo();
      final future = service.incomingCallStream.first;
      service.pushIncomingCall(info);
      expect(service.incomingCall, info);
      expect(await future, info);
    });

    test('overwrites previous call', () {
      final first = _makeInfo(name: 'Alice');
      final second = _makeInfo(name: 'Bob');
      service.pushIncomingCall(first);
      service.pushIncomingCall(second);
      expect(service.incomingCall!.callerName, 'Bob');
    });
  });

  // ── resetIncomingCall ───────────────────────────────────────

  group('resetIncomingCall', () {
    test('clears stored call', () {
      service.pushIncomingCall(_makeInfo());
      service.resetIncomingCall();
      expect(service.incomingCall, isNull);
    });
  });

  // ── stopRinging ─────────────────────────────────────────────

  group('stopRinging', () {
    test('cancels timer and delegates stop', () {
      fakeAsync((async) {
        var fired = false;
        service.startRingingTimer(const Duration(seconds: 30), () => fired = true);
        service.stopRinging();
        async.elapse(const Duration(seconds: 31));
        expect(fired, false);
        expect(fakeRingtone.stopped, true);
      });
    });

    test('handles null ringtone service', () {
      final bare = CallRingingService();
      expect(() => bare.stopRinging(), returnsNormally);
      bare.dispose();
    });
  });

  // ── playRingtone / playDialtone ─────────────────────────────

  group('playRingtone', () {
    test('delegates to ringtone service', () {
      service.playRingtone();
      expect(fakeRingtone.lastPlayed, 'ringtone');
    });

    test('handles null ringtone service', () {
      final bare = CallRingingService();
      expect(() => bare.playRingtone(), returnsNormally);
      bare.dispose();
    });
  });

  group('playDialtone', () {
    test('delegates to ringtone service', () {
      service.playDialtone();
      expect(fakeRingtone.lastPlayed, 'dialtone');
    });

    test('handles null ringtone service', () {
      final bare = CallRingingService();
      expect(() => bare.playDialtone(), returnsNormally);
      bare.dispose();
    });
  });

  // ── startRingingTimer ───────────────────────────────────────

  group('startRingingTimer', () {
    test('fires callback after duration', () {
      fakeAsync((async) {
        var fired = false;
        service.startRingingTimer(const Duration(seconds: 10), () => fired = true);
        async.elapse(const Duration(seconds: 9));
        expect(fired, false);
        async.elapse(const Duration(seconds: 1));
        expect(fired, true);
      });
    });

    test('restart replaces timer', () {
      fakeAsync((async) {
        var firstFired = false;
        var secondFired = false;
        service.startRingingTimer(const Duration(seconds: 10), () => firstFired = true);
        async.elapse(const Duration(seconds: 5));
        service.startRingingTimer(const Duration(seconds: 10), () => secondFired = true);
        async.elapse(const Duration(seconds: 10));
        expect(firstFired, false);
        expect(secondFired, true);
      });
    });

    test('stopped by stopRinging', () {
      fakeAsync((async) {
        var fired = false;
        service.startRingingTimer(const Duration(seconds: 10), () => fired = true);
        service.stopRinging();
        async.elapse(const Duration(seconds: 11));
        expect(fired, false);
      });
    });
  });

  // ── dispose ─────────────────────────────────────────────────

  group('dispose', () {
    test('stops ringing and disposes ringtone', () {
      service.dispose();
      expect(fakeRingtone.stopped, true);
      expect(fakeRingtone.disposed, true);
    });
  });
}
