import 'package:flutter/material.dart';

import 'package:lattice/core/models/pending_attachment.dart';

class AttachmentPreviewBar extends StatelessWidget {
  const AttachmentPreviewBar({
    super.key,
    required this.attachments,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<PendingAttachment> attachments;
  final ValueChanged<int> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.tertiary, width: 3)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < attachments.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _AttachmentCard(
                        attachment: attachments[i],
                        onRemove: () => onRemove(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Clear all attachments',
            onPressed: onClearAll,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.attachment,
    required this.onRemove,
  });

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: attachment.isImage
                  ? Image.memory(
                      attachment.bytes,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            size: 24,
                            color: cs.onSurfaceVariant,
                          ),
                          Text(
                            attachment.name.contains('.')
                                ? attachment.name.split('.').last
                                : attachment.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: SizedBox(
              width: 18,
              height: 18,
              child: IconButton(
                onPressed: onRemove,
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                iconSize: 12,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest,
                  side: BorderSide(color: cs.outlineVariant, width: 0.5),
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
