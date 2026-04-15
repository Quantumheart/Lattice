import 'package:flutter_test/flutter_test.dart';

import 'package:kohera/features/calling/models/call_state.dart';

void main() {
  group('KoheraCallState', () {
    test('has all expected values', () {
      expect(KoheraCallState.values, [
        KoheraCallState.idle,
        KoheraCallState.ringingOutgoing,
        KoheraCallState.ringingIncoming,
        KoheraCallState.joining,
        KoheraCallState.connected,
        KoheraCallState.reconnecting,
        KoheraCallState.disconnecting,
        KoheraCallState.failed,
      ]);
    });
  });

  group('validCallTransitions', () {
    test('every state has an entry', () {
      for (final state in KoheraCallState.values) {
        expect(validCallTransitions, contains(state));
      }
    });

    test('idle can transition to joining, ringingOutgoing, ringingIncoming', () {
      expect(validCallTransitions[KoheraCallState.idle], {
        KoheraCallState.joining,
        KoheraCallState.ringingOutgoing,
        KoheraCallState.ringingIncoming,
      });
    });

    test('ringingOutgoing can transition to joining, connected, idle, failed', () {
      expect(validCallTransitions[KoheraCallState.ringingOutgoing], {
        KoheraCallState.joining,
        KoheraCallState.connected,
        KoheraCallState.idle,
        KoheraCallState.failed,
      });
    });

    test('ringingIncoming can transition to joining or idle', () {
      expect(validCallTransitions[KoheraCallState.ringingIncoming], {
        KoheraCallState.joining,
        KoheraCallState.idle,
      });
    });

    test('joining can transition to connected, idle, or failed', () {
      expect(validCallTransitions[KoheraCallState.joining], {
        KoheraCallState.connected,
        KoheraCallState.idle,
        KoheraCallState.failed,
      });
    });

    test('connected can transition to reconnecting, disconnecting, or failed', () {
      expect(validCallTransitions[KoheraCallState.connected], {
        KoheraCallState.reconnecting,
        KoheraCallState.disconnecting,
        KoheraCallState.failed,
      });
    });

    test('reconnecting can transition to connected, disconnecting, or failed', () {
      expect(validCallTransitions[KoheraCallState.reconnecting], {
        KoheraCallState.connected,
        KoheraCallState.disconnecting,
        KoheraCallState.failed,
      });
    });

    test('disconnecting can only transition to idle', () {
      expect(validCallTransitions[KoheraCallState.disconnecting], {
        KoheraCallState.idle,
      });
    });

    test('failed can transition to idle, joining, or ringingOutgoing', () {
      expect(validCallTransitions[KoheraCallState.failed], {
        KoheraCallState.idle,
        KoheraCallState.joining,
        KoheraCallState.ringingOutgoing,
      });
    });

    test('no state can transition to itself', () {
      for (final state in KoheraCallState.values) {
        expect(validCallTransitions[state], isNot(contains(state)));
      }
    });

    test('all target states are valid enum values', () {
      for (final targets in validCallTransitions.values) {
        for (final target in targets) {
          expect(KoheraCallState.values, contains(target));
        }
      }
    });
  });
}
