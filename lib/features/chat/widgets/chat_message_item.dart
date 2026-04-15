import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/widgets/delete_event_dialog.dart';
import 'package:kohera/features/chat/widgets/emoji_picker_sheet.dart';
import 'package:kohera/features/chat/widgets/long_press_wrapper.dart';
import 'package:kohera/features/chat/widgets/message_action_sheet.dart';
import 'package:kohera/features/chat/widgets/message_bubble.dart' show MessageBubble;
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/features/chat/widgets/read_receipts.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart';
import 'package:matrix/matrix.dart';

class ChatMessageItem extends StatelessWidget {
  const ChatMessageItem({
    required this.event,
    required this.isMe,
    required this.isFirst,
    required this.isMobile,
    required this.timeline,
    required this.client,
    required this.onToggleReaction,
    this.highlightedEventId,
    this.receiptMap = const {},
    this.onReply,
    this.onEdit,
    this.onPin,
    this.onTapReply,
    super.key,
  });

  final Event event;
  final bool isMe;
  final bool isFirst;
  final bool isMobile;
  final Timeline? timeline;
  final Client client;
  final String? highlightedEventId;
  final Map<String, List<Receipt>> receiptMap;
  final void Function(Event event)? onReply;
  final void Function(Event event)? onEdit;
  final Future<void> Function(Event event)? onPin;
  final void Function(Event event)? onTapReply;
  final Future<void> Function(Event event, String emoji) onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final isRedacted = event.redacted;
    final room = event.room;
    final isPinned = room.pinnedEventIds.contains(event.eventId);
    final canPin = !isRedacted &&
        room.canChangeStateEvent('m.room.pinned_events');

    final hasReactions = timeline != null &&
        event.hasAggregatedEvents(timeline!, RelationshipTypes.reaction);
    final receipts = receiptMap[event.eventId]
        ?.where((r) => r.user.id != event.senderId)
        .toList();

    Widget? reactionBubble;
    if (hasReactions) {
      reactionBubble = ReactionChips(
        event: event,
        timeline: timeline!,
        client: client,
        isMe: isMe,
        onToggle: (emoji) => onToggleReaction(event, emoji),
      );
    }

    Widget? subBubble;
    if (receipts != null && receipts.isNotEmpty) {
      subBubble = ReadReceiptsRow(
        receipts: receipts,
        client: client,
        isMe: isMe,
      );
    }

    final Widget content = MessageBubble(
      event: event,
      isMe: isMe,
      isFirst: isFirst,
      highlighted: event.eventId == highlightedEventId,
      isPinned: isPinned,
      timeline: timeline,
      onTapReply: isRedacted ? null : onTapReply,
      onReply: isRedacted ? null : () => onReply?.call(event),
      onEdit: !isRedacted && isMe ? () => onEdit?.call(event) : null,
      onDelete: !isRedacted && event.canRedact
          ? () => confirmAndDeleteEvent(context, event)
          : null,
      onReact: isRedacted
          ? null
          : () => showEmojiPickerSheet(
                context,
                (emoji) => onToggleReaction(event, emoji),
              ),
      onQuickReact: isRedacted
          ? null
          : (emoji) => onToggleReaction(event, emoji),
      onPin: canPin ? () => onPin?.call(event) : null,
      reactionBubble: reactionBubble,
      subBubble: subBubble,
    );

    if (isMobile) {
      return SwipeableMessage(
        onReply: () => onReply?.call(event),
        child: LongPressWrapper(
          onLongPress: (rect) =>
              _showMobileActions(context, rect, isPinned, canPin),
          child: content,
        ),
      );
    }
    return content;
  }

  void _showMobileActions(
    BuildContext context,
    Rect bubbleRect,
    bool isPinned,
    bool canPin,
  ) {
    if (event.redacted) return;

    final cs = Theme.of(context).colorScheme;
    final actions = <MessageAction>[
      MessageAction(
        label: 'Reply',
        icon: Icons.reply_rounded,
        onTap: () => onReply?.call(event),
      ),
      if (isMe)
        MessageAction(
          label: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () => onEdit?.call(event),
        ),
      MessageAction(
        label: 'React',
        icon: Icons.add_reaction_outlined,
        onTap: () => showEmojiPickerSheet(
          context,
          (emoji) => onToggleReaction(event, emoji),
        ),
      ),
      if (canPin)
        MessageAction(
          label: isPinned ? 'Unpin' : 'Pin',
          icon: isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          onTap: () => onPin?.call(event),
        ),
      MessageAction(
        label: 'Copy',
        icon: Icons.copy_rounded,
        onTap: () {
          final displayEvent = timeline != null
              ? event.getDisplayEvent(timeline!)
              : event;
          unawaited(
            Clipboard.setData(
              ClipboardData(text: stripReplyFallback(displayEvent.body)),
            ),
          );
        },
      ),
      if (event.canRedact)
        MessageAction(
          label: isMe ? 'Delete' : 'Remove',
          icon: Icons.delete_outline_rounded,
          onTap: () => confirmAndDeleteEvent(context, event),
          color: cs.error,
        ),
    ];

    showMessageActionSheet(
      context: context,
      event: event,
      isMe: isMe,
      bubbleRect: bubbleRect,
      actions: actions,
      timeline: timeline,
      onQuickReact: (emoji) => onToggleReaction(event, emoji),
    );
  }
}
