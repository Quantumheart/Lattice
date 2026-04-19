import 'package:flutter/material.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/inline_reply_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/message_bubble_link_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_timestamp.dart';
import 'package:matrix/matrix.dart';

String? extractReplyEventId(Map<String, Object?> content) {
  return content
      .tryGet<Map<String, Object?>>('m.relates_to')
      ?.tryGet<Map<String, Object?>>('m.in_reply_to')
      ?.tryGet<String>('event_id');
}

class MessageBubbleContent extends StatelessWidget {
  const MessageBubbleContent({
    required this.event,
    required this.isMe,
    required this.isFirst,
    required this.isPinned,
    required this.metrics,
    this.timeline,
    this.onTapReply,
    super.key,
  });

  final Event event;
  final bool isMe;
  final bool isFirst;
  final bool isPinned;
  final DensityMetrics metrics;
  final Timeline? timeline;
  final void Function(Event)? onTapReply;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isRedacted = event.redacted;
    final displayEvent =
        timeline != null ? event.getDisplayEvent(timeline!) : event;
    final isEdited = !isRedacted &&
        timeline != null &&
        event.hasAggregatedEvents(timeline!, RelationshipTypes.edit);

    final replyEventId = extractReplyEventId(event.content);

    final bodyText = replyEventId != null
        ? stripReplyFallback(displayEvent.body)
        : displayEvent.body;

    final isTextMessage = !isRedacted &&
        (displayEvent.messageType == MessageTypes.Text ||
            displayEvent.messageType == MessageTypes.Notice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyEventId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InlineReplyPreview(
              event: event,
              timeline: timeline,
              isMe: isMe,
              onTap: onTapReply,
            ),
          ),
        if (!isMe && isFirst)
          Padding(
            padding: EdgeInsets.only(bottom: metrics.senderNameBottomPad),
            child: Text(
              event.senderFromMemoryOrFallback.displayName ?? event.senderId,
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: metrics.senderNameFontSize,
                color: senderColor(event.senderId, cs),
              ),
            ),
          ),
        MessageBubbleBody(
          event: event,
          displayEvent: displayEvent,
          bodyText: bodyText,
          isMe: isMe,
          metrics: metrics,
        ),
        if (isTextMessage)
          MessageBubbleLinkPreview(bodyText: bodyText, isMe: isMe),
        MessageBubbleTimestamp(
          event: event,
          isMe: isMe,
          isPinned: isPinned,
          isEdited: isEdited,
          metrics: metrics,
        ),
      ],
    );
  }
}
