import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../utils/sender_color.dart';
import 'message_bubble.dart' show stripReplyFallback;

// ── Inline reply preview ──────────────────────────────────────

class InlineReplyPreview extends StatefulWidget {
  const InlineReplyPreview({
    super.key,
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
  State<InlineReplyPreview> createState() => _InlineReplyPreviewState();
}

class _InlineReplyPreviewState extends State<InlineReplyPreview> {
  Event? _parentEvent;
  bool _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadParent();
  }

  @override
  void didUpdateWidget(InlineReplyPreview oldWidget) {
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
