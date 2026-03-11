import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/utils/format_file_size.dart';

void main() {
  group('formatFileSize', () {
    test('bytes', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('kilobytes', () {
      expect(formatFileSize(1024), '1.0 KB');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(1024 * 1023), '1023.0 KB');
    });

    test('megabytes', () {
      expect(formatFileSize(1024 * 1024), '1.0 MB');
      expect(formatFileSize((1.5 * 1024 * 1024).toInt()), '1.5 MB');
    });

    test('gigabytes', () {
      expect(formatFileSize(1024 * 1024 * 1024), '1.0 GB');
      expect(formatFileSize((2.5 * 1024 * 1024 * 1024).toInt()), '2.5 GB');
    });
  });
}
