import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../../services/preferences_service.dart';
import '../../utils/media_auth.dart';
import '../../utils/sender_color.dart';
import '../full_image_view.dart';
import '../user_avatar.dart';
import 'html_message_text.dart';
import 'linkable_text.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.isFirst,
    this.highlighted = false,
    this.timeline,
    this.onTapReply,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReact,
  });

  final Event event;
  final bool isMe;

  /// Whether this is the first message in a group from the same sender.
  final bool isFirst;

  /// Whether this message should be visually highlighted (e.g. from search).
  final bool highlighted;

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

  /// Returns the total horizontal offset of the sender avatar area
  /// (avatar diameter + gap), for use by external widgets like
  /// [ReactionChips] and [ReadReceiptsRow].
  static double avatarOffset(MessageDensity density) =>
      _DensityMetrics.of(density).avatarRadius * 2 + 8;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth * 0.72;
    final density = context.watch<PreferencesService>().messageDensity;
    final metrics = _DensityMetrics.of(density);
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

          // Hover reply button (before bubble for isMe)
          if (isDesktop && _hovering && widget.onReply != null && widget.isMe)
            _HoverReplyButton(cs: cs, onReply: widget.onReply!),

          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: EdgeInsets.symmetric(
                horizontal: metrics.bubbleHorizontalPad,
                vertical: metrics.bubbleVerticalPad,
              ),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? cs.primary
                    : cs.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(metrics.bubbleRadius),
                  topRight: Radius.circular(metrics.bubbleRadius),
                  bottomLeft: Radius.circular(widget.isMe
                      ? metrics.bubbleRadius
                      : (widget.isFirst ? 4 : metrics.bubbleRadius)),
                  bottomRight: Radius.circular(widget.isMe
                      ? (widget.isFirst ? 4 : metrics.bubbleRadius)
                      : metrics.bubbleRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Inline reply preview
                  if (replyEventId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _InlineReplyPreview(
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
                          bottom: metrics.senderNameBottomPad),
                      child: Text(
                        widget.event.senderFromMemoryOrFallback
                                .displayName ??
                            widget.event.senderId,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: metrics.senderNameFontSize,
                          color: senderColor(widget.event.senderId, cs),
                        ),
                      ),
                    ),

                  // Body
                  _buildBody(context, metrics, bodyText),

                  // Timestamp
                  Padding(
                    padding: EdgeInsets.only(top: metrics.timestampTopPad),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEdited)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '(edited)',
                              style: tt.bodyMedium?.copyWith(
                                fontSize: metrics.timestampFontSize,
                                color: widget.isMe
                                    ? cs.onPrimary.withValues(alpha: 0.6)
                                    : cs.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        Text(
                          _formatTime(widget.event.originServerTs),
                          style: tt.bodyMedium?.copyWith(
                            fontSize: metrics.timestampFontSize,
                            color: widget.isMe
                                ? cs.onPrimary.withValues(alpha: 0.6)
                                : cs.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        if (widget.isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            widget.event.status.isSent
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

          // Hover reply button (after bubble for non-me)
          if (isDesktop && _hovering && widget.onReply != null && !widget.isMe)
            _HoverReplyButton(cs: cs, onReply: widget.onReply!),

          // Sender avatar (only for first in group, me)
          if (widget.isMe && widget.isFirst)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: UserAvatar(
                client: widget.event.room.client,
                avatarUrl:
                    widget.event.senderFromMemoryOrFallback.avatarUrl,
                userId: widget.event.senderId,
                size: metrics.avatarRadius * 2,
              ),
            )
          else if (widget.isMe)
            SizedBox(width: metrics.avatarRadius * 2 + 8),
        ],
      ),
    );

    // Desktop: hover detection + right-click context menu
    if (isDesktop) {
      bubble = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
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
    if (value == 'copy') {
      final displayEvent = widget.timeline != null
          ? widget.event.getDisplayEvent(widget.timeline!)
          : widget.event;
      Clipboard.setData(ClipboardData(text: stripReplyFallback(displayEvent.body)));
    }
    if (value == 'delete') widget.onDelete?.call();
  }

  Widget _buildBody(
      BuildContext context, _DensityMetrics metrics, String bodyText) {
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
      return _ImageBubble(event: widget.event);
    }

    if (widget.event.messageType == MessageTypes.Video ||
        widget.event.messageType == MessageTypes.Audio ||
        widget.event.messageType == MessageTypes.File) {
      return _FileBubble(
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

  String _formatTime(DateTime ts) {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
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

// ── Inline reply preview ──────────────────────────────────────

class _InlineReplyPreview extends StatefulWidget {
  const _InlineReplyPreview({
    required this.event,
    required this.timeline,
    required this.isMe,
    this.onTap,
  });

  final Event event;
  final Timeline? timeline;
  final bool isMe;
  final void Function(Event)? onTap;

  @override
  State<_InlineReplyPreview> createState() => _InlineReplyPreviewState();
}

class _InlineReplyPreviewState extends State<_InlineReplyPreview> {
  Event? _parentEvent;
  bool _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadParent();
  }

  @override
  void didUpdateWidget(_InlineReplyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event != widget.event || oldWidget.timeline != widget.timeline) {
      _generation++;
      _loaded = false;
      _parentEvent = null;
      _loadParent();
    }
  }

  Future<void> _loadParent() async {
    final gen = _generation;
    if (widget.timeline == null) {
      if (mounted && gen == _generation) setState(() => _loaded = true);
      return;
    }
    try {
      final parent = await widget.event.getReplyEvent(widget.timeline!);
      if (mounted && gen == _generation) {
        setState(() {
          _parentEvent = parent;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to load reply parent: $e');
      if (mounted && gen == _generation) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final parentAvailable =
        _parentEvent != null &&
        _parentEvent!.type != EventTypes.Redaction &&
        !_parentEvent!.redacted;
    final senderName = parentAvailable
        ? (_parentEvent!.senderFromMemoryOrFallback.displayName ??
            _parentEvent!.senderId)
        : null;
    final color = parentAvailable
        ? senderColor(_parentEvent!.senderId, cs)
        : cs.onSurfaceVariant;

    return GestureDetector(
      onTap: parentAvailable ? () => widget.onTap?.call(_parentEvent!) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 2)),
          color: widget.isMe
              ? cs.onPrimary.withValues(alpha: 0.12)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: parentAvailable
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    senderName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    stripReplyFallback(_parentEvent!.body),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: widget.isMe
                          ? cs.onPrimary.withValues(alpha: 0.7)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Text(
                'Message not available',
                style: tt.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: widget.isMe
                      ? cs.onPrimary.withValues(alpha: 0.5)
                      : cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
      ),
    );
  }
}

// ── Hover reply button ────────────────────────────────────────

class _HoverReplyButton extends StatelessWidget {
  const _HoverReplyButton({required this.cs, required this.onReply});

  final ColorScheme cs;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onReply,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.reply_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
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

// ── File bubble (video / audio / generic file) ───────────────

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.event, required this.isMe});

  final Event event;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = isMe ? cs.onPrimary : cs.onSurface;

    final icon = switch (event.messageType) {
      MessageTypes.Video => Icons.videocam_rounded,
      MessageTypes.Audio => Icons.audiotrack_rounded,
      _ => Icons.insert_drive_file_rounded,
    };

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
                    _formatFileSize(fileSize),
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

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ── Image bubble (async URI resolution) ──────────────────────

class _ImageBubble extends StatefulWidget {
  const _ImageBubble({required this.event});

  final Event event;

  @override
  State<_ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<_ImageBubble> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_ImageBubble old) {
    super.didUpdateWidget(old);
    if (old.event.eventId != widget.event.eventId) {
      _imageBytes = null;
      _imageUrl = null;
      _loading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      if (widget.event.isAttachmentEncrypted) {
        final file = await widget.event.downloadAndDecryptAttachment(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _imageBytes = file.bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.event.getAttachmentUri(
          getThumbnail: true,
          width: 280,
          height: 260,
          method: ThumbnailMethod.scale,
        );
        if (mounted) {
          setState(() {
            _imageUrl = uri?.toString();
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Image bubble load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => showFullImageDialog(context, widget.event),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
          child: _loading
              ? Container(
                  height: 80,
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _imageBytes != null
                  ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? Image.network(
                          _imageUrl!,
                          fit: BoxFit.cover,
                          headers: mediaAuthHeaders(
                            widget.event.room.client,
                            _imageUrl!,
                          ),
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        )
                      : Container(
                          height: 80,
                          color: cs.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
        ),
      ),
    );
  }
}
