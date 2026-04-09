import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/utils/platform_info_web.dart';

void main() {
  group('isTouchDevice (web)', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('returns true for Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isTouchDevice, isTrue);
    });

    test('returns true for iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isTouchDevice, isTrue);
    });

    test('returns false for Linux', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(isTouchDevice, isFalse);
    });

    test('returns false for macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(isTouchDevice, isFalse);
    });

    test('returns false for Windows', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(isTouchDevice, isFalse);
    });
  });
}
