import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lattice/core/models/upload_state.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/chat/widgets/file_send_handler.dart';

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
    final bytes = await file.readAsBytes();
    await sendFileBytes(
      scaffold: scaffold,
      room: room,
      name: file.name,
      bytes: bytes,
      uploadNotifier: uploadNotifier,
    );
  }
}
