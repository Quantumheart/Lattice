import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/app_config.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(rootBundle.clear);
  tearDown(() {
    AppConfig.reset();
    rootBundle.clear();
  });

  void setAsset(String content) {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/config/app_config.json') {
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
      }
      return null;
    });
  }

  void clearAssetHandler() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  }

  group('AppConfig.load', () {
    test('parses defaultHomeserver from JSON', () async {
      setAsset('{"defaultHomeserver": "example.com"}');
      await AppConfig.load();
      expect(AppConfig.instance.defaultHomeserver, 'example.com');
      clearAssetHandler();
    });

    test('falls back to matrix.org when key is missing', () async {
      setAsset('{}');
      await AppConfig.load();
      expect(AppConfig.instance.defaultHomeserver, 'matrix.org');
      clearAssetHandler();
    });

    test('falls back to matrix.org on malformed JSON', () async {
      setAsset('not valid json {{{');
      await AppConfig.load();
      expect(AppConfig.instance.defaultHomeserver, 'matrix.org');
      clearAssetHandler();
    });

    test('falls back to matrix.org when asset is missing', () async {
      binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async => null);
      await AppConfig.load();
      expect(AppConfig.instance.defaultHomeserver, 'matrix.org');
      clearAssetHandler();
    });
  });

  group('AppConfig.instance', () {
    test('throws assertion when accessed before load', () {
      expect(() => AppConfig.instance, throwsA(isA<AssertionError>()));
    });
  });
}
