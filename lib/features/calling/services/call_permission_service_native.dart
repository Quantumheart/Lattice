import 'package:kohera/core/services/macos_permissions.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:permission_handler/permission_handler.dart';

// coverage:ignore-start
abstract class CallPermissionService {
  static Future<bool> request() async {
    if (isNativeMacOS) return MacOsPermissions.requestCameraAndMicrophone();
    if (!(isNativeAndroid || isNativeIOS)) return true;

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
    if (isNativeMacOS) {
      final camera = await MacOsPermissions.checkMedia('camera');
      final mic = await MacOsPermissions.checkMedia('microphone');
      return camera && mic;
    }
    if (!(isNativeAndroid || isNativeIOS)) return true;

    final camera = await Permission.camera.isGranted;
    final microphone = await Permission.microphone.isGranted;
    return camera && microphone;
  }
}
// coverage:ignore-end
