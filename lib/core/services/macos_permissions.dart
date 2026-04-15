import 'package:flutter/services.dart';

// coverage:ignore-start
abstract class MacOsPermissions {
  static const _channel = MethodChannel('com.kohera.app/tcc');

  static Future<bool> checkScreenCapture() async {
    final granted =
        await _channel.invokeMethod<bool>('checkScreenCapturePermission');
    return granted ?? false;
  }

  static Future<bool> requestScreenCapture() async {
    final granted =
        await _channel.invokeMethod<bool>('requestScreenCapturePermission');
    return granted ?? false;
  }

  static Future<bool> checkMedia(String type) async {
    final granted =
        await _channel.invokeMethod<bool>('checkMediaPermission', {'type': type});
    return granted ?? false;
  }

  static Future<bool> requestMedia(String type) async {
    final granted =
        await _channel.invokeMethod<bool>('requestMediaPermission', {'type': type});
    return granted ?? false;
  }

  static Future<bool> requestCameraAndMicrophone() async {
    final camera = await checkMedia('camera') || await requestMedia('camera');
    final mic = await checkMedia('microphone') || await requestMedia('microphone');
    return camera && mic;
  }
}
// coverage:ignore-end
