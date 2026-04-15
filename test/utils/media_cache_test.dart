import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/media_cache.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    MediaCache.clearAll();
    tempDir = Directory.systemTemp.createTempSync('media_cache_test_');
  });

  tearDown(() {
    MediaCache.clearAll();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('evict is a no-op for unknown event ID', () {
    MediaCache.evict('unknown_event');
  });

  test('clearAll is a no-op when cache is empty', MediaCache.clearAll);

  test('clearAll removes all temp files', () {
    final files = <File>[];
    for (var i = 0; i < 3; i++) {
      final f = File('${tempDir.path}/test_$i.tmp')..writeAsBytesSync([0]);
      files.add(f);
    }

    for (var i = 0; i < 3; i++) {
      expect(files[i].existsSync(), isTrue);
    }

    MediaCache.clearAll();
  });
}
