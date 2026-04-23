import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_content.dart';
import 'package:kohera/features/chat/widgets/message_bubble_context_menu.dart';
import 'package:kohera/features/chat/widgets/message_bubble_hover_bar_slot.dart';
import 'package:kohera/features/chat/widgets/message_bubble_skin.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    required this.event, required this.isMe, required this.isFirst, super.key,
    this.highlighted = false,
    this.isPinned = false,
    this.timeline,
    this.onTapReply,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReact,
    this.onQuickReact,
    this.onPin,
    this.reactionBubble,
    this.subBubble,
  });

  final Event event;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  /// Whether this message should be visually highlighted (e.g. from search).
  final bool highlighted;

  /// Whether this message is pinned in the room.
  final bool isPinned;

  /// Timeline for resolving reply parent events.
  final Timeline? timeline;

  /// Called when user taps an inline reply preview to scroll to the parent.
  final void Function(Event)? onTapReply;

  /// Called to initiate a reply to this message.
  final VoidCallback? onReply;

  /// Called to initiate editing this message (own messages only).
  final VoidCallback? onEdit;

  /// Called to delete/redact this message.
  final VoidCallback? onDelete;

  /// Called to open the emoji picker for reacting to this message.
  final VoidCallback? onReact;

  /// Called with a specific emoji for quick-reacting to this message.
  final void Function(String emoji)? onQuickReact;

  /// Called to pin or unpin this message.
  final VoidCallback? onPin;

  /// Reaction chips overlapping the bottom edge of the bubble (Signal-style).
  final Widget? reactionBubble;

  /// Widget displayed below the bubble (e.g. read receipts).
  final Widget? subBubble;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final ValueNotifier<bool> _hovering = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _quickReactOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovering.dispose();
    _quickReactOpen.dispose();
    super.dispose();
  }

  void _openContextMenu(Offset position) {
    unawaited(showMessageContextMenu(
      context,
      event: widget.event,
      isMe: widget.isMe,
      isPinned: widget.isPinned,
      timeline: widget.timeline,
      position: position,
      onReply: widget.onReply,
      onEdit: widget.onEdit,
      onReact: widget.onReact,
      onPin: widget.onPin,
      onDelete: widget.onDelete,
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final isDesktop = !isTouchDevice;

    Widget bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: EdgeInsets.only(
        top: widget.isFirst
            ? metrics.firstMessageTopPad
            : metrics.messageTopPad,
        bottom: metrics.messageBottomPad,
      ),
      decoration: BoxDecoration(
        color: widget.highlighted
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isMe) _avatarSlot(showAvatar: widget.isFirst, metrics: metrics),
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MessageBubbleHoverBarSlot(
                      enabled: isDesktop && widget.isMe,
                      hovering: _hovering,
                      onReact: widget.onReact,
                      onQuickReact: widget.onQuickReact,
                      onReply: widget.onReply,
                      onMore: _openContextMenu,
                      onQuickReactOpenChanged: (open) =>
                          _quickReactOpen.value = open,
                    ),
                    Flexible(
                      child: RepaintBoundary(
                        child: MessageBubbleSkin(
                          isMe: widget.isMe,
                          isFirst: widget.isFirst,
                          metrics: metrics,
                          reactionBubble: widget.reactionBubble,
                          child: MessageBubbleContent(
                            event: widget.event,
                            isMe: widget.isMe,
                            isFirst: widget.isFirst,
                            isPinned: widget.isPinned,
                            metrics: metrics,
                            timeline: widget.timeline,
                            onTapReply: widget.onTapReply,
                          ),
                        ),
                      ),
                    ),
                    MessageBubbleHoverBarSlot(
                      enabled: isDesktop && !widget.isMe,
                      hovering: _hovering,
                      onReact: widget.onReact,
                      onQuickReact: widget.onQuickReact,
                      onReply: widget.onReply,
                      onMore: _openContextMenu,
                      onQuickReactOpenChanged: (open) =>
                          _quickReactOpen.value = open,
                    ),
                    if (widget.isMe)
                      _avatarSlot(showAvatar: widget.isFirst, metrics: metrics),
                  ],
                ),
                if (widget.subBubble != null) widget.subBubble!,
              ],
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      bubble = MouseRegion(
        onEnter: (_) => _hovering.value = true,
        onExit: (_) {
          if (!_quickReactOpen.value) _hovering.value = false;
        },
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              _openContextMenu(event.position);
            }
          },
          child: bubble,
        ),
      );
    }

    return bubble;
  }

  Widget _avatarSlot({
    required bool showAvatar,
    required DensityMetrics metrics,
  }) {
    if (showAvatar) {
      return Padding(
        padding: EdgeInsets.only(
          left: widget.isMe ? 8 : 0,
          right: widget.isMe ? 0 : 8,
        ),
        child: UserAvatar(
          client: widget.event.room.client,
          avatarUrl: widget.event.senderFromMemoryOrFallback.avatarUrl,
          userId: widget.event.senderId,
          size: metrics.avatarRadius * 2,
        ),
      );
    }
    return SizedBox(width: metrics.avatarRadius * 2 + 8);
  }
}
