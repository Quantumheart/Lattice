import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../models/upload_state.dart';
import '../../services/matrix_service.dart';

/// Picks a file and sends it to [roomId] via the Matrix SDK.
Future<void> pickAndSendFile(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final matrix = context.read<MatrixService>();

  final result = await FilePicker.platform.pickFiles(
    type: FileType.any,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;

  final picked = result.files.first;
  final bytes = picked.bytes;
  final name = picked.name;
  if (bytes == null) return;

  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );
  final room = matrix.client.getRoomById(roomId);
  if (room == null) {
    uploadNotifier.value = null;
    return;
  }

  try {
    final file = MatrixFile.fromMimeType(bytes: bytes, name: name);
    await room.sendFileEvent(file);
    uploadNotifier.value = null;
  } on FileTooBigMatrixException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      const SnackBar(content: Text('File too large for this server')),
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
