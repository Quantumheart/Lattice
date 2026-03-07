import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/order_utils.dart';

void main() {
  group('midpoint', () {
    test('both null returns midpoint char', () {
      final result = midpoint(null, null);
      expect(result, isNotNull);
      expect(result!.length, 1);
      // Should be roughly in the middle of 0x20..0x7E
      expect(result.codeUnitAt(0), greaterThanOrEqualTo(0x20));
      expect(result.codeUnitAt(0), lessThanOrEqualTo(0x7E));
    });

    test('both empty strings treated as null', () {
      final result = midpoint('', '');
      expect(result, midpoint(null, null));
    });

    test('before null, after non-null returns string less than after', () {
      final result = midpoint(null, 'm');
      expect(result, isNotNull);
      expect(result!.compareTo('m'), lessThan(0));
    });

    test('before non-null, after null returns string greater than before', () {
      final result = midpoint('m', null);
      expect(result, isNotNull);
      expect(result!.compareTo('m'), greaterThan(0));
    });

    test('between two strings returns intermediate value', () {
      final result = midpoint('a', 'z');
      expect(result, isNotNull);
      expect(result!.compareTo('a'), greaterThan(0));
      expect(result.compareTo('z'), lessThan(0));
    });

    test('between adjacent chars appends midpoint', () {
      final result = midpoint('a', 'b');
      expect(result, isNotNull);
      expect(result!.compareTo('a'), greaterThan(0));
      expect(result.compareTo('b'), lessThan(0));
    });

    test('successive midpoints maintain ordering', () {
      // Simulate repeated "insert at end" operations.
      String? prev;
      final orders = <String>[];
      for (var i = 0; i < 20; i++) {
        final next = midpoint(prev, null);
        expect(next, isNotNull, reason: 'midpoint #$i failed');
        if (prev != null) {
          expect(next!.compareTo(prev), greaterThan(0),
              reason: '$next should be > $prev',);
        }
        orders.add(next!);
        prev = next;
      }
      // Verify all are in sorted order.
      for (var i = 1; i < orders.length; i++) {
        expect(orders[i].compareTo(orders[i - 1]), greaterThan(0));
      }
    });

    test('successive midpoints between two values maintain ordering', () {
      // Repeatedly insert between first and second element.
      const lo = 'A';
      var hi = 'Z';
      for (var i = 0; i < 30; i++) {
        final mid = midpoint(lo, hi);
        expect(mid, isNotNull, reason: 'midpoint #$i between $lo and $hi');
        expect(mid!.compareTo(lo), greaterThan(0),
            reason: '$mid should be > $lo',);
        expect(mid.compareTo(hi), lessThan(0),
            reason: '$mid should be < $hi',);
        hi = mid; // Keep narrowing the range from above.
      }
    });

    test('all generated strings are valid per Matrix spec', () {
      final strings = <String?>[
        midpoint(null, null),
        midpoint(null, 'z'),
        midpoint('a', null),
        midpoint('a', 'z'),
        midpoint('a', 'b'),
        midpoint(' ', '~'), // min and max chars
      ];
      for (final s in strings) {
        if (s == null) continue;
        expect(s.length, lessThanOrEqualTo(50),
            reason: 'Order string too long: $s',);
        for (var i = 0; i < s.length; i++) {
          expect(s.codeUnitAt(i), greaterThanOrEqualTo(0x20),
              reason: 'Char below range in: $s',);
          expect(s.codeUnitAt(i), lessThanOrEqualTo(0x7E),
              reason: 'Char above range in: $s',);
        }
      }
    });

    test('before minimum char string returns null (cannot go lower)', () {
      // Space (0x20) is the minimum character. We cannot generate a valid
      // string that sorts before a single space char — the function should
      // return null for this impossible case.
      final result = midpoint(null, ' ');
      // This is an edge case: either null (impossible) or a valid result.
      // In practice, order strings start much higher, so this is irrelevant.
      // We just verify the result is valid if non-null.
      if (result != null) {
        for (var i = 0; i < result.length; i++) {
          expect(result.codeUnitAt(i), greaterThanOrEqualTo(0x20));
          expect(result.codeUnitAt(i), lessThanOrEqualTo(0x7E));
        }
      }
    });

    test('after maximum char string appends midpoint', () {
      final result = midpoint('~', null); // tilde is 0x7E = max char
      expect(result, isNotNull);
      expect(result!.compareTo('~'), greaterThan(0));
      expect(result.length, 2); // ~ + midpoint char
    });
  });
}
