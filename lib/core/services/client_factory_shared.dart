import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

const Set<String> callPreviewTypes = {
  EventTypes.CallInvite,
  EventTypes.CallAnswer,
  EventTypes.CallReject,
  EventTypes.CallHangup,
  EventTypes.GroupCallMember,
};

Client buildClient(
  String clientName,
  MatrixSdkDatabase database,
  NativeImplementations nativeImplementations,
  Future<void> Function(Client)? onSoftLogout,
) {
  final client = Client(
    'Kohera ($clientName)',
    database: database,
    logLevel: kReleaseMode ? Level.warning : Level.verbose,
    defaultNetworkRequestTimeout: const Duration(minutes: 2),
    onSoftLogout: onSoftLogout,
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    },
    nativeImplementations: nativeImplementations,
  );
  client.roomPreviewLastEvents.removeAll(callPreviewTypes);
  return client;
}
