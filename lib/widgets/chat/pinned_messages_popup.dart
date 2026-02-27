import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../user_avatar.dart';
import 'message_bubble.dart' show stripReplyFallback;

/// Shows a popup panel anchored below the pin icon listing pinned messages.
void showPinnedMessagesPopup(
  BuildContext context,
  Room room, {
  required void Function(Event event) onTap,
}) {
  final button = context.findRenderObject() as RenderBox;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final buttonPos = button.localToGlobal(Offset.zero, ancestor: overlay);
  final anchor = Rect.fromLTWH(
    buttonPos.dx,
    buttonPos.dy,
    button.size.width,
    button.size.height,
  );

  Navigator.of(context).push(
    _PinnedMessagesPopupRoute(
      anchor: anchor,
      overlaySize: overlay.size,
      room: room,
      onTap: onTap,
    ),
  );
}

class _PinnedMessagesPopupRoute extends PopupRoute<void> {
  _PinnedMessagesPopupRoute({
    required this.anchor,
    required this.overlaySize,
    required this.room,
    required this.onTap,
  });

  final Rect anchor;
  final Size overlaySize;
  final Room room;
  final void Function(Event event) onTap;

  @override
  Color? get barrierColor => Colors.black26;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss pinned messages';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomSingleChildLayout(
        delegate: _PopupLayoutDelegate(
          anchor: anchor,
          containerSize: constraints.biggest,
        ),
        child: FadeTransition(
          opacity: animation,
          child: _PinnedMessagesPanel(
            room: room,
            onTap: onTap,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

// ── Popup positioning ──────────────────────────────────────────────

class _PopupLayoutDelegate extends SingleChildLayoutDelegate {
  _PopupLayoutDelegate({required this.anchor, required this.containerSize});

  final Rect anchor;
  final Size containerSize;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: 420.0.clamp(0, constraints.maxWidth - 16),
      maxHeight: 400.0.clamp(0, constraints.maxHeight - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Right-align with the button's right edge
    var dx = anchor.right - childSize.width;
    dx = dx.clamp(8.0, size.width - childSize.width - 8);

    // Place below the button
    var dy = anchor.bottom + 4;
    if (dy + childSize.height > size.height - 8) {
      dy = size.height - childSize.height - 8;
    }

    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_PopupLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor ||
        containerSize != oldDelegate.containerSize;
  }
}

// ── Panel content ──────────────────────────────────────────────────

class _PinnedMessagesPanel extends StatefulWidget {
  const _PinnedMessagesPanel({
    required this.room,
    required this.onTap,
    required this.onClose,
  });

  final Room room;
  final void Function(Event event) onTap;
  final VoidCallback onClose;

  @override
  State<_PinnedMessagesPanel> createState() => _PinnedMessagesPanelState();
}

class _PinnedMessagesPanelState extends State<_PinnedMessagesPanel> {
  List<Event>? _pinnedEvents;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPinnedEvents();
  }

  Future<void> _loadPinnedEvents() async {
    final ids = widget.room.pinnedEventIds;
    final results = await Future.wait(
      ids.map((id) => widget.room.getEventById(id).catchError((e) {
            debugPrint('[Lattice] Failed to load pinned event $id: $e');
            return null;
          })),
    );
    if (mounted) {
      setState(() {
        _pinnedEvents = results.whereType<Event>().toList();
        _loading = false;
      });
    }
  }

  Future<void> _unpin(String eventId) async {
    try {
      final pinned = List<String>.from(widget.room.pinnedEventIds);
      pinned.remove(eventId);
      await widget.room.setPinnedEvents(pinned);
      if (mounted) {
        setState(() {
          _pinnedEvents?.removeWhere((e) => e.eventId == eventId);
        });
        if (_pinnedEvents?.isEmpty ?? true) widget.onClose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unpin message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canPin =
        widget.room.canChangeStateEvent('m.room.pinned_events');

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: cs.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
            child: Row(
              children: [
                Text(
                  'Pinned Messages',
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
          // Content
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_pinnedEvents == null || _pinnedEvents!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No pinned messages',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _pinnedEvents!.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
                itemBuilder: (context, i) {
                  final event = _pinnedEvents![i];
                  return _PinnedMessageTile(
                    event: event,
                    canUnpin: canPin,
                    onOpen: () {
                      widget.onClose();
                      widget.onTap(event);
                    },
                    onUnpin: () => _unpin(event.eventId),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Individual pinned message tile ─────────────────────────────────

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({
    required this.event,
    required this.canUnpin,
    required this.onOpen,
    required this.onUnpin,
  });

  final Event event;
  final bool canUnpin;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sender = event.senderFromMemoryOrFallback;
    final displayName = sender.displayName ?? event.senderId;
    final body = stripReplyFallback(event.body);
    final time = _formatDateTime(event.originServerTs);

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar, name, time, actions
            Row(
              children: [
                UserAvatar(
                  client: event.room.client,
                  avatarUrl: sender.avatarUrl,
                  userId: event.senderId,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                _ActionChip(
                  label: 'Open',
                  onTap: onOpen,
                ),
                if (canUnpin) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      onPressed: onUnpin,
                      tooltip: 'Unpin',
                    ),
                  ),
                ],
              ],
            ),
            // Body text
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime ts) {
    final now = DateTime.now();
    final isToday = ts.year == now.year &&
        ts.month == now.month &&
        ts.day == now.day;
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    if (isToday) return '$h:$m';
    final d = ts.day.toString().padLeft(2, '0');
    final mo = ts.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Ink(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
