import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppConfig {
  AppConfig._({
    required this.defaultHomeserver,
    this.webPushGatewayUrl,
    this.vapidPublicKey,
  });

  final String defaultHomeserver;
  final String? webPushGatewayUrl;
  final String? vapidPublicKey;

  bool get webPushConfigured =>
      webPushGatewayUrl != null && vapidPublicKey != null;

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
    String? webPushGatewayUrl,
    String? vapidPublicKey,
  }) {
    return AppConfig._(
      defaultHomeserver: defaultHomeserver,
      webPushGatewayUrl: webPushGatewayUrl,
      vapidPublicKey: vapidPublicKey,
    );
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
        webPushGatewayUrl: json['webPushGatewayUrl'] as String?,
        vapidPublicKey: json['vapidPublicKey'] as String?,
      );
    } catch (e) {
      debugPrint('[Lattice] Failed to load app config: $e');
      _instance = AppConfig._(
        defaultHomeserver: _fallbackHomeserver,
      );
    }
  }
}
