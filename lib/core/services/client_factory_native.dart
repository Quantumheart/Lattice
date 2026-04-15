import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:kohera/core/services/client_factory_shared.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _apnsChannel = MethodChannel('kohera/apns');

Future<String> _getIosDatabasePath(String clientName) async {
  try {
    final appGroupPath =
        await _apnsChannel.invokeMethod<String>('getAppGroupPath');
    if (appGroupPath != null) {
      final sharedPath = p.join(appGroupPath, 'kohera_$clientName.db');
      debugPrint('[Kohera] iOS database path: $sharedPath');
      return sharedPath;
    }
  } catch (e) {
    debugPrint('[Kohera] Failed to get App Group path: $e');
  }
  final dir = await getApplicationSupportDirectory();
  final fallbackPath = p.join(dir.path, 'kohera_$clientName.db');
  debugPrint('[Kohera] iOS database path (fallback): $fallbackPath');
  return fallbackPath;
}

// coverage:ignore-start
Future<Client> createDefaultClient(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
}) async {
  final Database sqfliteDb;
  if (Platform.isIOS) {
    final dbPath = await _getIosDatabasePath(clientName);
    sqfliteDb = await sqflite_native.openDatabase(dbPath);
  } else if (Platform.isAndroid) {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kohera_$clientName.db');
    sqfliteDb = await sqflite_native.openDatabase(dbPath);
  } else {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'kohera_$clientName.db');
    sqfliteDb = await dbFactory.openDatabase(dbPath);
  }
  final database = await MatrixSdkDatabase.init(
    'kohera_$clientName',
    database: sqfliteDb,
  );
  return buildClient(
    clientName,
    database,
    NativeImplementationsIsolate(compute, vodozemacInit: vod.init),
    onSoftLogout,
  );
}
// coverage:ignore-end
