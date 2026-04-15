import 'package:flutter/material.dart';
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/read_file_bytes.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

Future<void> sendVoiceMessage(
  BuildContext context,
  String roomId,
  ValueNotifier<UploadState?> uploadNotifier,
  String filePath,
  Duration duration,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final matrix = context.read<MatrixService>();
  final room = matrix.client.getRoomById(roomId);
  if (room == null) return;

  final bytes = await readFileBytes(filePath);
  final name = filePath.split('/').last;

  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );

  try {
    final matrixFile = MatrixAudioFile(bytes: bytes, name: name);
    await room.sendFileEvent(
      matrixFile,
      extraContent: {
        'info': {
          'duration': duration.inMilliseconds,
          'mimetype': 'audio/ogg',
          'size': bytes.length,
        },
        'org.matrix.msc3245.voice': <String, dynamic>{},
      },
    );
    uploadNotifier.value = null;
  } on FileTooBigMatrixException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      const SnackBar(content: Text('Voice message too large for this server')),
    );
  } catch (e) {
    uploadNotifier.value = UploadState(
      status: UploadStatus.error,
      fileName: name,
      error: e.toString(),
    );
    scaffold.showSnackBar(
      SnackBar(
          content: Text(
              'Upload failed: ${MatrixService.friendlyAuthError(e)}',),),
    );
  } finally {
    try {
      await deleteFile(filePath);
    } catch (_) {}
  }
}
// coverage:ignore-end
