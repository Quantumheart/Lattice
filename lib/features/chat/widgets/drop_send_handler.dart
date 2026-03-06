import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/matrix_service.dart';

Future<void> sendDroppedFiles(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
  List<DropItem> files,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final matrix = context.read<MatrixService>();
  final room = matrix.client.getRoomById(roomId);
  if (room == null) return;

  for (final file in files) {
    final name = file.name;
    uploadNotifier.value = UploadState(
      status: UploadStatus.uploading,
      fileName: name,
    );

    try {
      final Uint8List bytes = await file.readAsBytes();
      final matrixFile = MatrixFile.fromMimeType(bytes: bytes, name: name);
      await room.sendFileEvent(matrixFile);
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
}
