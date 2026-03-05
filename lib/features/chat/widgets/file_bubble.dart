import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/core/utils/format_file_size.dart';

// ── File bubble (generic file attachment) ─────────────────────

class FileBubble extends StatelessWidget {
  const FileBubble({super.key, required this.event, required this.isMe});

  final Event event;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = isMe ? cs.onPrimary : cs.onSurface;

    const icon = Icons.insert_drive_file_rounded;

    final fileName = event.body;
    final infoMap = event.content.tryGet<Map<String, Object?>>('info');
    final fileSize = infoMap?.tryGet<int>('size');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: foreground.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (fileSize != null)
                  Text(
                    formatFileSize(fileSize),
                    style: tt.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
