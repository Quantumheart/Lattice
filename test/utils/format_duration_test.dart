import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/format_duration.dart';

void main() {
  group('formatDuration', () {
    test('zero duration returns 00:00', () {
      expect(formatDuration(Duration.zero), '00:00');
    });

    test('seconds only pads correctly', () {
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(seconds: 59)), '00:59');
    });

    test('minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 1, seconds: 30)), '01:30');
      expect(formatDuration(const Duration(minutes: 10, seconds: 5)), '10:05');
    });

    test('hours are expressed as minutes', () {
      expect(formatDuration(const Duration(hours: 1)), '60:00');
      expect(formatDuration(const Duration(hours: 1, minutes: 5, seconds: 3)), '65:03');
    });
  });
}
