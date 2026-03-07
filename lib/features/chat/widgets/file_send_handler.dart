import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

Future<void> pickAndSendFile(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final matrix = context.read<MatrixService>();

  final result = await FilePicker.platform.pickFiles(
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;

  final picked = result.files.first;
  final bytes = picked.bytes;
  final name = picked.name;
  if (bytes == null) return;

  final room = matrix.client.getRoomById(roomId);
  if (room == null) return;

  await sendFileBytes(
    scaffold: scaffold,
    room: room,
    name: name,
    bytes: bytes,
    uploadNotifier: uploadNotifier,
  );
}

Future<void> sendFileBytes({
  required ScaffoldMessengerState scaffold,
  required Room room,
  required String name,
  required Uint8List bytes,
  required ValueNotifier<UploadState?> uploadNotifier,
}) async {
  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );

  try {
    final file = MatrixFile.fromMimeType(bytes: bytes, name: name);
    await room.sendFileEvent(file);
    uploadNotifier.value = null;
  } on FileTooBigMatrixException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      SnackBar(content: Text('File too large: $name')),
    );
  } catch (e) {
    uploadNotifier.value = UploadState(
      status: UploadStatus.error,
      fileName: name,
      error: e.toString(),
    );
    scaffold.showSnackBar(
      SnackBar(content: Text('Upload failed: ${MatrixService.friendlyAuthError(e)}')),
    );
  }
}
