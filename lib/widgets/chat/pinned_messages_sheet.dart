import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../user_avatar.dart';
import 'message_bubble.dart' show stripReplyFallback;

/// Shows a modal bottom sheet listing all pinned messages in a room.
void showPinnedMessagesSheet(
  BuildContext context,
  Room room, {
  required void Function(Event event) onTap,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PinnedMessagesSheet(room: room, onTap: onTap),
  );
}

class _PinnedMessagesSheet extends StatefulWidget {
  const _PinnedMessagesSheet({required this.room, required this.onTap});

  final Room room;
  final void Function(Event event) onTap;

  @override
  State<_PinnedMessagesSheet> createState() => _PinnedMessagesSheetState();
}

class _PinnedMessagesSheetState extends State<_PinnedMessagesSheet> {
  List<Event>? _pinnedEvents;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPinnedEvents();
  }

  Future<void> _loadPinnedEvents() async {
    final ids = widget.room.pinnedEventIds;
    final events = <Event>[];
    for (final id in ids) {
      try {
        final event = await widget.room.getEventById(id);
        if (event != null) events.add(event);
      } catch (e) {
        debugPrint('[Lattice] Failed to load pinned event $id: $e');
      }
    }
    if (mounted) {
      setState(() {
        _pinnedEvents = events;
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

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('Pinned Messages', style: tt.titleMedium),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _pinnedEvents == null || _pinnedEvents!.isEmpty
                      ? Center(
                          child: Text(
                            'No pinned messages',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _pinnedEvents!.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 64),
                          itemBuilder: (context, i) {
                            final event = _pinnedEvents![i];
                            return _PinnedMessageTile(
                              event: event,
                              canUnpin: canPin,
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onTap(event);
                              },
                              onUnpin: () => _unpin(event.eventId),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({
    required this.event,
    required this.canUnpin,
    required this.onTap,
    required this.onUnpin,
  });

  final Event event;
  final bool canUnpin;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sender = event.senderFromMemoryOrFallback;
    final displayName = sender.displayName ?? event.senderId;
    final body = stripReplyFallback(event.body);
    final time = _formatDateTime(event.originServerTs);

    return ListTile(
      leading: UserAvatar(
        client: event.room.client,
        avatarUrl: sender.avatarUrl,
        userId: event.senderId,
        size: 36,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            time,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      subtitle: Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: canUnpin
          ? IconButton(
              icon: Icon(Icons.push_pin_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              tooltip: 'Unpin',
              onPressed: onUnpin,
            )
          : null,
      onTap: onTap,
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
