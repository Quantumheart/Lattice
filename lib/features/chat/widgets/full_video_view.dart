import 'package:flutter/material.dart';
import 'package:lattice/shared/widgets/media_viewer_shell.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ── Fullscreen video dialog ───────────────────────────────────

void showFullVideoDialog(
  BuildContext context, {
  required Event event,
  required Player player,
  required VideoController controller,
}) {
  showMediaViewer(
    context,
    event: event,
    child: Video(controller: controller),
  );
}
