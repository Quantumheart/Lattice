import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ── Fullscreen video dialog ───────────────────────────────────

void showFullVideoDialog(
  BuildContext context, {
  required Player player,
  required VideoController controller,
}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: FullVideoView(player: player, controller: controller),
    ),
  );
}

class FullVideoView extends StatelessWidget {
  const FullVideoView({
    super.key,
    required this.player,
    required this.controller,
  });

  final Player player;
  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = screenSize.width - 32;
    final maxHeight = screenSize.height - 32;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Video(controller: controller),
      ),
    );
  }
}
