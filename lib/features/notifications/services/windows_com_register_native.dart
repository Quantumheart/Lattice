import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';

Future<void> registerWindowsComServer() async {
  const keyPath =
      r'HKCU\Software\Classes\CLSID\{' +
      NotificationChannel.windowsGuid +
      r'}\LocalServer32';
  final exe = Platform.resolvedExecutable;
  final result =
      await Process.run('reg', ['add', keyPath, '/ve', '/d', exe, '/f']);
  if (result.exitCode != 0) {
    debugPrint(
      '[Lattice] Failed to register Windows COM server: ${result.stderr}',
    );
  } else {
    debugPrint('[Lattice] Windows COM server registered at $exe');
  }
}
