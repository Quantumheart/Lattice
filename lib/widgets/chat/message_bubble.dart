import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../services/preferences_service.dart';
import '../../utils/sender_color.dart';
import '../user_avatar.dart';
import 'density_metrics.dart';
import 'file_bubble.dart';
import 'hover_action_bar.dart';
import 'html_message_text.dart';
import 'image_bubble.dart';
import 'inline_reply_preview.dart';
import 'link_preview_card.dart';
import 'linkable_text.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirst,
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
  bool _hovering = false;
  bool _quickReactOpen = false;
  String? _cachedPreviewUrl;
  String? _previewUrlBody;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth * 0.72;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = DensityMetrics.of(density);
    final isDesktop = screenWidth >= 720;

    final isRedacted = widget.event.redacted;

    // Resolve edits: use the display event for rendered content.
    final displayEvent = widget.timeline != null
        ? widget.event.getDisplayEvent(widget.timeline!)
        : widget.event;
    final isEdited = !isRedacted &&
        widget.timeline != null &&
        widget.event.hasAggregatedEvents(
            widget.timeline!, RelationshipTypes.edit);

    final replyEventId = widget.event.content
            .tryGet<Map<String, Object?>>('m.relates_to')
            ?.tryGet<Map<String, Object?>>('m.in_reply_to')
            ?.tryGet<String>('event_id');

    // Strip reply fallback from body text for events that are replies.
    final bodyText = replyEventId != null
        ? stripReplyFallback(displayEvent.body)
        : displayEvent.body;

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
          // Sender avatar (only for first in group)
          if (!widget.isMe && widget.isFirst)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UserAvatar(
                client: widget.event.room.client,
                avatarUrl:
                    widget.event.senderFromMemoryOrFallback.avatarUrl,
                userId: widget.event.senderId,
                size: metrics.avatarRadius * 2,
              ),
            )
          else if (!widget.isMe)
            SizedBox(width: metrics.avatarRadius * 2 + 8),

          // Bubble + overlapping reactions + sub-bubble (receipts)
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Hover action bar (before bubble for isMe)
                    if (isDesktop && _hovering && widget.isMe)
                      HoverActionBar(
                        cs: cs,
                        onReact: widget.onReact,
                        onQuickReact: widget.onQuickReact,
                        onReply: widget.onReply,
                        onMore: (pos) => _showContextMenu(context, pos),
                        onQuickReactOpenChanged: (open) =>
                            setState(() => _quickReactOpen = open),
                      ),
                    Flexible(
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: widget.isMe
                            ? AlignmentDirectional.topEnd
                            : AlignmentDirectional.topStart,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  widget.reactionBubble != null ? 22 : 0,
                            ),
                            child: Container(
                              constraints:
                                  BoxConstraints(maxWidth: maxWidth),
                              padding: EdgeInsets.symmetric(
                                horizontal: metrics.bubbleHorizontalPad,
                                vertical: metrics.bubbleVerticalPad,
                              ),
                              decoration: BoxDecoration(
                                color: widget.isMe
                                    ? cs.primary
                                    : cs.primaryContainer
                                        .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(
                                      metrics.bubbleRadius),
                                  topRight: Radius.circular(
                                      metrics.bubbleRadius),
                                  bottomLeft: Radius.circular(widget.isMe
                                      ? metrics.bubbleRadius
                                      : (widget.isFirst
                                          ? 4
                                          : metrics.bubbleRadius)),
                                  bottomRight: Radius.circular(widget.isMe
                                      ? (widget.isFirst
                                          ? 4
                                          : metrics.bubbleRadius)
                                      : metrics.bubbleRadius),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // Inline reply preview
                                  if (replyEventId != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: 4),
                                      child: InlineReplyPreview(
                                        event: widget.event,
                                        timeline: widget.timeline,
                                        isMe: widget.isMe,
                                        onTap: widget.onTapReply,
                                      ),
                                    ),

                                  // Sender name (first in group, non-me)
                                  if (!widget.isMe && widget.isFirst)
                                    Padding(
                                      padding: EdgeInsets.only(
                                          bottom:
                                              metrics.senderNameBottomPad),
                                      child: Text(
                                        widget.event
                                                .senderFromMemoryOrFallback
                                                .displayName ??
                                            widget.event.senderId,
                                        style: tt.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize:
                                              metrics.senderNameFontSize,
                                          color: senderColor(
                                              widget.event.senderId, cs),
                                        ),
                                      ),
                                    ),

                                  // Body
                                  _buildBody(context, metrics, bodyText),

                                  // Link preview
                                  if (_isTextMessage &&
                                      context.select<PreferencesService, bool>((p) => p.showLinkPreviews))
                                    _buildLinkPreview(bodyText),

                                  // Timestamp
                                  Padding(
                                    padding: EdgeInsets.only(
                                        top: metrics.timestampTopPad),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.isPinned)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(
                                                    right: 4),
                                            child: Icon(
                                              Icons.push_pin_rounded,
                                              size:
                                                  metrics.timestampFontSize +
                                                      2,
                                              color: widget.isMe
                                                  ? cs.onPrimary.withValues(
                                                      alpha: 0.6)
                                                  : cs.onSurfaceVariant
                                                      .withValues(
                                                          alpha: 0.5),
                                            ),
                                          ),
                                        if (isEdited)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(
                                                    right: 4),
                                            child: Text(
                                              '(edited)',
                                              style:
                                                  tt.bodyMedium?.copyWith(
                                                fontSize: metrics
                                                    .timestampFontSize,
                                                color: widget.isMe
                                                    ? cs.onPrimary
                                                        .withValues(
                                                            alpha: 0.6)
                                                    : cs.onSurfaceVariant
                                                        .withValues(
                                                            alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                        Text(
                                          _formatTime(widget
                                              .event.originServerTs),
                                          style: tt.bodyMedium?.copyWith(
                                            fontSize:
                                                metrics.timestampFontSize,
                                            color: widget.isMe
                                                ? cs.onPrimary.withValues(
                                                    alpha: 0.6)
                                                : cs.onSurfaceVariant
                                                    .withValues(
                                                        alpha: 0.5),
                                          ),
                                        ),
                                        if (widget.isMe) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            widget.event.status.isSent
                                                ? Icons.done_all_rounded
                                                : Icons.done_rounded,
                                            size: metrics.statusIconSize,
                                            color: cs.onPrimary
                                                .withValues(alpha: 0.6),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (widget.reactionBubble != null)
                            Positioned(
                              bottom: 0,
                              left: widget.isMe ? null : 12,
                              right: widget.isMe ? 12 : null,
                              child: widget.reactionBubble!,
                            ),
                        ],
                      ),
                    ),
                    // Hover action bar (after bubble for non-me)
                    if (isDesktop && _hovering && !widget.isMe)
                      HoverActionBar(
                        cs: cs,
                        onReact: widget.onReact,
                        onQuickReact: widget.onQuickReact,
                        onReply: widget.onReply,
                        onMore: (pos) => _showContextMenu(context, pos),
                        onQuickReactOpenChanged: (open) =>
                            setState(() => _quickReactOpen = open),
                      ),
                    // Sender avatar (isMe, inside bubble Row to avoid
                    // overlapping read receipts below)
                    if (widget.isMe && widget.isFirst)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: UserAvatar(
                          client: widget.event.room.client,
                          avatarUrl: widget.event
                              .senderFromMemoryOrFallback.avatarUrl,
                          userId: widget.event.senderId,
                          size: metrics.avatarRadius * 2,
                        ),
                      )
                    else if (widget.isMe)
                      SizedBox(width: metrics.avatarRadius * 2 + 8),
                  ],
                ),
                if (widget.subBubble != null) widget.subBubble!,
              ],
            ),
          ),
        ],
      ),
    );

    // Desktop: hover detection + right-click context menu
    if (isDesktop) {
      bubble = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) {
          if (!_quickReactOpen) setState(() => _hovering = false);
        },
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: bubble,
        ),
      );
    }

    return bubble;
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final cs = Theme.of(context).colorScheme;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: cs.surfaceContainer,
      items: [
        if (widget.onReply != null)
          const PopupMenuItem(
            value: 'reply',
            child: Row(
              children: [
                Icon(Icons.reply_rounded, size: 18),
                SizedBox(width: 8),
                Text('Reply'),
              ],
            ),
          ),
        if (widget.onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_rounded, size: 18),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
        if (widget.onReact != null)
          const PopupMenuItem(
            value: 'react',
            child: Row(
              children: [
                Icon(Icons.add_reaction_outlined, size: 18),
                SizedBox(width: 8),
                Text('React'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
        ),
        if (widget.onPin != null)
          PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  widget.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(widget.isPinned ? 'Unpin' : 'Pin'),
              ],
            ),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Text(widget.isMe ? 'Delete' : 'Remove', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
      ],
    );
    if (!mounted) return;
    if (value == 'reply') widget.onReply?.call();
    if (value == 'react') widget.onReact?.call();
    if (value == 'edit') widget.onEdit?.call();
    if (value == 'pin') widget.onPin?.call();
    if (value == 'copy') {
      final displayEvent = widget.timeline != null
          ? widget.event.getDisplayEvent(widget.timeline!)
          : widget.event;
      Clipboard.setData(ClipboardData(text: stripReplyFallback(displayEvent.body)));
    }
    if (value == 'delete') widget.onDelete?.call();
  }

  Widget _buildBody(
      BuildContext context, DensityMetrics metrics, String bodyText) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (widget.event.redacted) {
      final redactor = widget.event.redactedBecause?.senderId;
      final isSelfRedact = redactor == widget.event.senderId;
      String label;
      if (widget.isMe) {
        label = 'You deleted this message';
      } else if (isSelfRedact) {
        label = 'This message was deleted';
      } else if (redactor != null) {
        final redactorUser =
            widget.event.room.unsafeGetUserFromMemoryOrFallback(redactor);
        final displayName = redactorUser.displayName ?? redactor;
        label = 'Deleted by $displayName';
      } else {
        label = 'This message was deleted';
      }
      return Text(
        label,
        style: tt.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: widget.isMe
              ? cs.onPrimary.withValues(alpha: 0.5)
              : cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
    }

    if (widget.event.messageType == MessageTypes.Image) {
      return ImageBubble(event: widget.event);
    }

    if (widget.event.messageType == MessageTypes.Video ||
        widget.event.messageType == MessageTypes.Audio ||
        widget.event.messageType == MessageTypes.File) {
      return FileBubble(
        event: widget.event,
        isMe: widget.isMe,
      );
    }

    // Check for HTML formatted body.
    final formattedBody = widget.event.formattedText;
    final hasHtml = formattedBody.isNotEmpty &&
        widget.event.content['format'] == 'org.matrix.custom.html';

    final textStyle = tt.bodyLarge?.copyWith(
      color: widget.isMe ? cs.onPrimary : cs.onSurface,
      fontSize: metrics.bodyFontSize,
      height: metrics.bodyLineHeight,
    );

    if (hasHtml) {
      return HtmlMessageText(
        html: formattedBody,
        style: textStyle,
        isMe: widget.isMe,
        room: widget.event.room,
      );
    }

    return LinkableText(
      text: bodyText,
      style: textStyle,
      isMe: widget.isMe,
    );
  }

  /// Whether the event is a plain text or notice message (not image/file/etc).
  bool get _isTextMessage {
    final type = widget.event.messageType;
    return !widget.event.redacted &&
        (type == MessageTypes.Text || type == MessageTypes.Notice);
  }

  /// Extract the first http(s) URL from [body], skipping matrix.to links.
  static String? _extractFirstUrl(String body) {
    for (final match in LinkableText.urlRegex.allMatches(body)) {
      final url = LinkableText.cleanUrl(match.group(0)!);
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host != 'matrix.to') return url;
    }
    return null;
  }

  Widget _buildLinkPreview(String bodyText) {
    // Cache the extracted URL to avoid re-running the regex on every build.
    if (_previewUrlBody != bodyText) {
      _previewUrlBody = bodyText;
      _cachedPreviewUrl = _extractFirstUrl(bodyText);
    }
    final url = _cachedPreviewUrl;
    if (url == null) return const SizedBox.shrink();
    return LinkPreviewCard(url: url, isMe: widget.isMe);
  }

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    final time = '$h:$m';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(msgDate).inDays;

    if (diff == 0) return time;
    if (diff == 1) return 'Yesterday $time';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    if (diff < 7) return '${weekdays[ts.weekday - 1]} $time';
    if (ts.year == now.year) return '${months[ts.month - 1]} ${ts.day}, $time';
    return '${months[ts.month - 1]} ${ts.day}, ${ts.year}, $time';
  }
}

/// Strip the `> ` reply fallback lines from a Matrix message body.
/// Handles both `> text` and bare `>` lines per the Matrix spec.
String stripReplyFallback(String body) {
  final lines = body.split('\n');
  int i = 0;
  while (i < lines.length && (lines[i].startsWith('> ') || lines[i] == '>')) {
    i++;
  }
  // Skip the blank line after the fallback block.
  if (i < lines.length && lines[i].isEmpty) i++;
  return lines.sublist(i).join('\n');
}
