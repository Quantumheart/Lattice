import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite_native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates a configured [Client] instance with platform-specific database.
Future<Client> createDefaultClient(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
}) async {
  final Database sqfliteDb;
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    sqfliteDb = await sqflite_native.openDatabase(dbPath);
  } else {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lattice_$clientName.db');
    sqfliteDb = await dbFactory.openDatabase(dbPath);
  }
  final database = await MatrixSdkDatabase.init(
    'lattice_$clientName',
    database: sqfliteDb,
  );
  return Client(
    'Lattice ($clientName)',
    database: database,
    logLevel: kReleaseMode ? Level.warning : Level.verbose,
    defaultNetworkRequestTimeout: const Duration(minutes: 2),
    onSoftLogout: onSoftLogout,
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    },
    nativeImplementations: NativeImplementationsIsolate(
      compute,
      vodozemacInit: vod.init,
    ),
  );
}
