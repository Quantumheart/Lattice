import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/utils/time_format.dart';

void main() {
  group('formatRelativeTimestamp', () {
    test('returns "now" for timestamps less than a minute ago', () {
      final ts = DateTime.now().subtract(const Duration(seconds: 30));
      expect(formatRelativeTimestamp(ts), 'now');
    });

    test('returns HH:mm for timestamps less than 24 hours ago', () {
      final ts = DateTime.now().subtract(const Duration(hours: 2));
      final result = formatRelativeTimestamp(ts);
      // Should be in HH:mm format.
      expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(result), isTrue);
    });

    test('returns Nd ago for timestamps within the last week', () {
      final ts = DateTime.now().subtract(const Duration(days: 3));
      expect(formatRelativeTimestamp(ts), '3d ago');
    });

    test('returns dd/mm for timestamps older than a week', () {
      final ts = DateTime.now().subtract(const Duration(days: 30));
      final result = formatRelativeTimestamp(ts);
      expect(RegExp(r'^\d{2}/\d{2}$').hasMatch(result), isTrue);
    });

    test('returns 1d ago for exactly one day', () {
      final ts = DateTime.now().subtract(const Duration(hours: 25));
      expect(formatRelativeTimestamp(ts), '1d ago');
    });

    test('returns 6d ago for six days', () {
      final ts = DateTime.now().subtract(const Duration(days: 6));
      expect(formatRelativeTimestamp(ts), '6d ago');
    });
  });
}
