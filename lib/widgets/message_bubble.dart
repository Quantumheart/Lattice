import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirst,
  });

  final Event event;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? 10 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sender avatar (only for first in group, non-me)
          if (!isMe && isFirst)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: _senderColor(event.senderId, cs),
                child: Text(
                  _senderInitial(event),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (!isMe)
            const SizedBox(width: 36),

          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isMe
                    ? cs.primary
                    : cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : (isFirst ? 4 : 18)),
                  bottomRight:
                      Radius.circular(isMe ? (isFirst ? 4 : 18) : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name (first in group, non-me)
                  if (!isMe && isFirst)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        event.senderFromMemoryOrFallback.displayName ??
                            event.senderId,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: _senderColor(event.senderId, cs),
                        ),
                      ),
                    ),

                  // Body
                  _buildBody(context),

                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(event.originServerTs),
                          style: tt.bodyMedium?.copyWith(
                            fontSize: 10,
                            color: isMe
                                ? cs.onPrimary.withValues(alpha: 0.6)
                                : cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            event.status.isSent
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 13,
                            color: cs.onPrimary.withValues(alpha: 0.6),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (event.messageType == MessageTypes.Image) {
      final imageUrl = event.attachmentMxcUrl?.toString();
      if (imageUrl == null || imageUrl.isEmpty) {
        return Container(
          height: 80,
          color: cs.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxHeight: 260, maxWidth: 280),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 80,
              color: cs.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    }

    // Default: text
    return Text(
      event.body,
      style: tt.bodyLarge?.copyWith(
        color: isMe ? cs.onPrimary : cs.onSurface,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }

  Color _senderColor(String senderId, ColorScheme cs) {
    final hash = senderId.codeUnits.fold<int>(0, (h, c) => h + c);
    final palette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
      const Color(0xFF6750A4),
      const Color(0xFFB4846C),
      const Color(0xFF7C9A6E),
      const Color(0xFFC17B5F),
    ];
    return palette[hash % palette.length];
  }

  String _senderInitial(Event event) {
    final name =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
