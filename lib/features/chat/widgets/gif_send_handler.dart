import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kohera/core/models/upload_state.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

// coverage:ignore-start

Future<void> sendGifFromUrl({
  required ScaffoldMessengerState scaffold,
  required Room room,
  required String url,
  required String title,
  required ValueNotifier<UploadState?> uploadNotifier,
}) async {
  final name = '${title.replaceAll(RegExp(r'[^\w\s-]'), '')}.gif';
  uploadNotifier.value = UploadState(
    status: UploadStatus.uploading,
    fileName: name,
  );

  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download GIF');
    }

    final file = MatrixFile.fromMimeType(bytes: response.bodyBytes, name: name);
    await room.sendFileEvent(file);
    uploadNotifier.value = null;
  } on FileTooBigMatrixException {
    uploadNotifier.value = null;
    scaffold.showSnackBar(
      SnackBar(content: Text('GIF too large: $name')),
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
          'GIF send failed: ${MatrixService.friendlyAuthError(e)}',
        ),
      ),
    );
  }
}
// coverage:ignore-end
