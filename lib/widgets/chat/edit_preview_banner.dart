import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'message_bubble.dart' show stripReplyFallback;

class EditPreviewBanner extends StatelessWidget {
  const EditPreviewBanner({
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

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
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
