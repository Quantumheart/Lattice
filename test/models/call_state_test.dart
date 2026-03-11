import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/features/calling/models/call_state.dart';

void main() {
  group('LatticeCallState', () {
    test('has all expected values', () {
      expect(LatticeCallState.values, [
        LatticeCallState.idle,
        LatticeCallState.ringingOutgoing,
        LatticeCallState.ringingIncoming,
        LatticeCallState.joining,
        LatticeCallState.connected,
        LatticeCallState.reconnecting,
        LatticeCallState.disconnecting,
        LatticeCallState.failed,
      ]);
    });
  });

  group('validCallTransitions', () {
    test('every state has an entry', () {
      for (final state in LatticeCallState.values) {
        expect(validCallTransitions, contains(state));
      }
    });

    test('idle can transition to joining, ringingOutgoing, ringingIncoming', () {
      expect(validCallTransitions[LatticeCallState.idle], {
        LatticeCallState.joining,
        LatticeCallState.ringingOutgoing,
        LatticeCallState.ringingIncoming,
      });
    });

    test('ringingOutgoing can transition to joining, connected, idle, failed', () {
      expect(validCallTransitions[LatticeCallState.ringingOutgoing], {
        LatticeCallState.joining,
        LatticeCallState.connected,
        LatticeCallState.idle,
        LatticeCallState.failed,
      });
    });

    test('ringingIncoming can transition to joining or idle', () {
      expect(validCallTransitions[LatticeCallState.ringingIncoming], {
        LatticeCallState.joining,
        LatticeCallState.idle,
      });
    });

    test('joining can transition to connected, idle, or failed', () {
      expect(validCallTransitions[LatticeCallState.joining], {
        LatticeCallState.connected,
        LatticeCallState.idle,
        LatticeCallState.failed,
      });
    });

    test('connected can transition to reconnecting, disconnecting, or failed', () {
      expect(validCallTransitions[LatticeCallState.connected], {
        LatticeCallState.reconnecting,
        LatticeCallState.disconnecting,
        LatticeCallState.failed,
      });
    });

    test('reconnecting can transition to connected, disconnecting, or failed', () {
      expect(validCallTransitions[LatticeCallState.reconnecting], {
        LatticeCallState.connected,
        LatticeCallState.disconnecting,
        LatticeCallState.failed,
      });
    });

    test('disconnecting can only transition to idle', () {
      expect(validCallTransitions[LatticeCallState.disconnecting], {
        LatticeCallState.idle,
      });
    });

    test('failed can transition to idle, joining, or ringingOutgoing', () {
      expect(validCallTransitions[LatticeCallState.failed], {
        LatticeCallState.idle,
        LatticeCallState.joining,
        LatticeCallState.ringingOutgoing,
      });
    });

    test('no state can transition to itself', () {
      for (final state in LatticeCallState.values) {
        expect(validCallTransitions[state], isNot(contains(state)));
      }
    });

    test('all target states are valid enum values', () {
      for (final targets in validCallTransitions.values) {
        for (final target in targets) {
          expect(LatticeCallState.values, contains(target));
        }
      }
    });
  });
}
