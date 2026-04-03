import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppConfig {
  AppConfig._({
    required this.defaultHomeserver,
  });

  final String defaultHomeserver;

  static AppConfig? _instance;

  static AppConfig get instance {
    assert(_instance != null, 'AppConfig.load() must be called before use');
    return _instance!;
  }

  static const String _assetPath = 'assets/config/app_config.json';

  static const String _fallbackHomeserver = 'matrix.org';

  @visibleForTesting
  factory AppConfig.testInstance({
    String defaultHomeserver = _fallbackHomeserver,
  }) {
    return AppConfig._(defaultHomeserver: defaultHomeserver);
  }

  @visibleForTesting
  static void setInstance(AppConfig config) => _instance = config;

  @visibleForTesting
  static void reset() => _instance = null;

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _instance = AppConfig._(
        defaultHomeserver:
            json['defaultHomeserver'] as String? ?? _fallbackHomeserver,
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to load app config: $e');
      _instance = AppConfig._(
        defaultHomeserver: _fallbackHomeserver,
      );
    }
  }
}
