import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/sender_color.dart';

void main() {
  final cs = ColorScheme.fromSeed(seedColor: Colors.blue);

  group('senderColor', () {
    test('returns a color from the palette', () {
      final color = senderColor('@alice:example.com', cs);
      final palette = [
        cs.primary,
        cs.tertiary,
        cs.secondary,
        cs.error,
        const Color(0xFF6750A4),
        const Color(0xFFB4846C),
        const Color(0xFF7C9A6E),
        const Color(0xFFC17B5F),
      ];
      expect(palette, contains(color));
    });

    test('is deterministic for the same sender', () {
      final a = senderColor('@bob:matrix.org', cs);
      final b = senderColor('@bob:matrix.org', cs);
      expect(a, equals(b));
    });

    test('different senders can produce different colors', () {
      final colors = <Color>{};
      for (final id in ['@a:x', '@b:x', '@c:x', '@d:x', '@e:x', '@f:x', '@g:x', '@h:x']) {
        colors.add(senderColor(id, cs));
      }
      expect(colors.length, greaterThan(1));
    });
  });
}
