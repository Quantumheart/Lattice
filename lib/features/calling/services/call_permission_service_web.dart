import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

abstract class CallPermissionService {
  static Future<bool> request() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
      );
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
      return true;
    } catch (e) {
      debugPrint('[Kohera] Failed to request media permissions: $e');
      return false;
    }
  }

  static Future<bool> check() async {
    try {
      final desc = {'name': 'microphone'}.jsify()! as JSObject;
      final status =
          await web.window.navigator.permissions.query(desc).toDart;
      return status.state == 'granted';
    } catch (e) {
      return false;
    }
  }
}
