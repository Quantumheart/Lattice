import 'package:flutter/foundation.dart';
import 'package:lattice/core/services/client_factory_shared.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

// coverage:ignore-start
Future<Client> createDefaultClient(
  String clientName, {
  Future<void> Function(Client)? onSoftLogout,
}) async {
  final database = await MatrixSdkDatabase.init('lattice_$clientName');
  return buildClient(
    clientName,
    database,
    NativeImplementationsIsolate(compute, vodozemacInit: vod.init),
    onSoftLogout,
  );
}
// coverage:ignore-end
