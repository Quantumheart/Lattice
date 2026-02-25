import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../utils/sender_color.dart';
import 'message_bubble.dart' show stripReplyFallback;

class ReplyPreviewBanner extends StatelessWidget {
  const ReplyPreviewBanner({
    super.key,
    required this.event,
    required this.onCancel,
  });

  final Event event;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = senderColor(event.senderId, cs);
    final senderName =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  stripReplyFallback(event.body),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
