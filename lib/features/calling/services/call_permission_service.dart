import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class CallPermissionService {
  static bool get _needsPermissionRequest =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static Future<bool> request() async {
    if (!_needsPermissionRequest) return true;
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final camera = statuses[Permission.camera]!;
    final microphone = statuses[Permission.microphone]!;

    if (camera.isPermanentlyDenied || microphone.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return camera.isGranted && microphone.isGranted;
  }

  static Future<bool> check() async {
    if (!_needsPermissionRequest) return true;
    final camera = await Permission.camera.isGranted;
    final microphone = await Permission.microphone.isGranted;
    return camera && microphone;
  }
}
