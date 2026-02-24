import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../services/preferences_service.dart';
import '../utils/media_auth.dart';
import '../utils/sender_color.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirst,
    this.highlighted = false,
  });

  final Event event;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  /// Whether this message should be visually highlighted (e.g. from search).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = _DensityMetrics.of(density);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: EdgeInsets.only(
        top: isFirst ? metrics.firstMessageTopPad : metrics.messageTopPad,
        bottom: metrics.messageBottomPad,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
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
                radius: metrics.avatarRadius,
                backgroundColor: senderColor(event.senderId, cs),
                child: Text(
                  _senderInitial(event),
                  style: TextStyle(
                    fontSize: metrics.avatarFontSize,
                    fontWeight: FontWeight.w600,
                    color: ThemeData.estimateBrightnessForColor(senderColor(event.senderId, cs)) == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ),
            )
          else if (!isMe)
            SizedBox(width: metrics.avatarRadius * 2 + 8),

          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: EdgeInsets.symmetric(
                horizontal: metrics.bubbleHorizontalPad,
                vertical: metrics.bubbleVerticalPad,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? cs.primary
                    : cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(metrics.bubbleRadius),
                  topRight: Radius.circular(metrics.bubbleRadius),
                  bottomLeft: Radius.circular(
                      isMe ? metrics.bubbleRadius : (isFirst ? 4 : metrics.bubbleRadius)),
                  bottomRight: Radius.circular(
                      isMe ? (isFirst ? 4 : metrics.bubbleRadius) : metrics.bubbleRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name (first in group, non-me)
                  if (!isMe && isFirst)
                    Padding(
                      padding: EdgeInsets.only(bottom: metrics.senderNameBottomPad),
                      child: Text(
                        event.senderFromMemoryOrFallback.displayName ??
                            event.senderId,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: metrics.senderNameFontSize,
                          color: senderColor(event.senderId, cs),
                        ),
                      ),
                    ),

                  // Body
                  _buildBody(context, metrics),

                  // Timestamp
                  Padding(
                    padding: EdgeInsets.only(top: metrics.timestampTopPad),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(event.originServerTs),
                          style: tt.bodyMedium?.copyWith(
                            fontSize: metrics.timestampFontSize,
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
                            size: metrics.statusIconSize,
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

  Widget _buildBody(BuildContext context, _DensityMetrics metrics) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (event.messageType == MessageTypes.Image) {
      final mxcUrl = event.attachmentMxcUrl;
      if (mxcUrl == null) {
        return Container(
          height: 80,
          color: cs.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        );
      }
      final httpUrl = mxcUrl.getThumbnailUri(
        event.room.client,
        width: 280,
        height: 260,
        method: ThumbnailMethod.scale,
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxHeight: 260, maxWidth: 280),
          child: Image.network(
            httpUrl.toString(),
            fit: BoxFit.cover,
            headers: mediaAuthHeaders(event.room.client, httpUrl.toString()),
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
        fontSize: metrics.bodyFontSize,
        height: metrics.bodyLineHeight,
      ),
    );
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

// ── Density metrics ──────────────────────────────────────────

class _DensityMetrics {
  const _DensityMetrics({
    required this.firstMessageTopPad,
    required this.messageTopPad,
    required this.messageBottomPad,
    required this.avatarRadius,
    required this.avatarFontSize,
    required this.bubbleHorizontalPad,
    required this.bubbleVerticalPad,
    required this.bubbleRadius,
    required this.senderNameBottomPad,
    required this.senderNameFontSize,
    required this.bodyFontSize,
    required this.bodyLineHeight,
    required this.timestampTopPad,
    required this.timestampFontSize,
    required this.statusIconSize,
  });

  final double firstMessageTopPad;
  final double messageTopPad;
  final double messageBottomPad;
  final double avatarRadius;
  final double avatarFontSize;
  final double bubbleHorizontalPad;
  final double bubbleVerticalPad;
  final double bubbleRadius;
  final double senderNameBottomPad;
  final double senderNameFontSize;
  final double bodyFontSize;
  final double bodyLineHeight;
  final double timestampTopPad;
  final double timestampFontSize;
  final double statusIconSize;

  static const _compact = _DensityMetrics(
    firstMessageTopPad: 6,
    messageTopPad: 1,
    messageBottomPad: 1,
    avatarRadius: 12,
    avatarFontSize: 9,
    bubbleHorizontalPad: 10,
    bubbleVerticalPad: 6,
    bubbleRadius: 16,
    senderNameBottomPad: 2,
    senderNameFontSize: 11,
    bodyFontSize: 13,
    bodyLineHeight: 1.3,
    timestampTopPad: 3,
    timestampFontSize: 9,
    statusIconSize: 12,
  );

  static const _default = _DensityMetrics(
    firstMessageTopPad: 10,
    messageTopPad: 2,
    messageBottomPad: 2,
    avatarRadius: 14,
    avatarFontSize: 11,
    bubbleHorizontalPad: 14,
    bubbleVerticalPad: 9,
    bubbleRadius: 18,
    senderNameBottomPad: 3,
    senderNameFontSize: 12,
    bodyFontSize: 14,
    bodyLineHeight: 1.4,
    timestampTopPad: 4,
    timestampFontSize: 10,
    statusIconSize: 13,
  );

  static const _comfortable = _DensityMetrics(
    firstMessageTopPad: 14,
    messageTopPad: 4,
    messageBottomPad: 4,
    avatarRadius: 16,
    avatarFontSize: 12,
    bubbleHorizontalPad: 16,
    bubbleVerticalPad: 12,
    bubbleRadius: 20,
    senderNameBottomPad: 4,
    senderNameFontSize: 13,
    bodyFontSize: 15,
    bodyLineHeight: 1.5,
    timestampTopPad: 5,
    timestampFontSize: 11,
    statusIconSize: 14,
  );

  static _DensityMetrics of(MessageDensity density) => switch (density) {
        MessageDensity.compact => _compact,
        MessageDensity.defaultDensity => _default,
        MessageDensity.comfortable => _comfortable,
      };
}
