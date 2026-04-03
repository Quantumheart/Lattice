import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  AppConfig._({
    required this.defaultHomeserver,
    required this.suggestedServers,
  });

  final String defaultHomeserver;
  final List<String> suggestedServers;

  static AppConfig? _instance;

  static AppConfig get instance {
    assert(_instance != null, 'AppConfig.load() must be called before use');
    return _instance!;
  }

  static const String _assetPath = 'assets/config/app_config.json';

  static const String _fallbackHomeserver = 'matrix.org';

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _instance = AppConfig._(
        defaultHomeserver:
            json['defaultHomeserver'] as String? ?? _fallbackHomeserver,
        suggestedServers: (json['suggestedServers'] as List<dynamic>?)
                ?.cast<String>() ??
            [_fallbackHomeserver],
      );
    } catch (_) {
      _instance = AppConfig._(
        defaultHomeserver: _fallbackHomeserver,
        suggestedServers: [_fallbackHomeserver],
      );
    }
  }
}
