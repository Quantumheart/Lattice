import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/notification_filter.dart';
import 'package:lattice/core/utils/order_utils.dart' as order_utils;
import 'package:lattice/core/utils/platform_info.dart';
import 'package:lattice/core/utils/reply_fallback.dart';
import 'package:lattice/features/calling/models/call_constants.dart';
import 'package:lattice/features/chat/widgets/typing_indicator.dart' show TypingIndicator;
import 'package:lattice/features/rooms/widgets/room_context_menu.dart';
import 'package:lattice/features/spaces/widgets/space_reparent_controller.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

bool get _isDesktop =>
    isNativeDesktop;

// ── Room tile ───────────────────────────────────────────────
class RoomTile extends StatelessWidget {
  const RoomTile({
    required this.room, required this.isSelected, required this.memberships, required this.hasContextMenu, super.key,
    this.parentSpaceId,
    this.sectionRooms,
  });

  final Room room;
  final bool isSelected;
  final Set<String> memberships;
  final bool hasContextMenu;
  final String? parentSpaceId;
  final List<Room>? sectionRooms;

  void _openContextMenu(BuildContext context, RelativeRect position) {
    if (!hasContextMenu) return;
    unawaited(showRoomContextMenu(
      context,
      position,
      room,
      parentSpaceId: parentSpaceId,
      sectionRooms: sectionRooms,
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<PreferencesService>();
    context.select<PreferencesService, (NotificationLevel, String, bool)>(
      (p) => (p.notificationLevel, p.notificationKeywords.join(','), p.typingIndicators),
    );
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final unread = effectiveUnreadCount(room, prefs);
    final lastEvent = room.lastEvent;
    final hasMenu = hasContextMenu;

    Widget tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          mouseCursor: SystemMouseCursors.click,
          onTap: () => context.goNamed(Routes.room, pathParameters: {'roomId': room.id}),
          onSecondaryTapUp: hasMenu
              ? (details) {
                  final overlay = Overlay.of(context).context
                      .findRenderObject()! as RenderBox;
                  _openContextMenu(
                    context,
                    RelativeRect.fromSize(
                      details.globalPosition & Size.zero,
                      overlay.size,
                    ),
                  );
                }
              : null,
          onLongPress: hasMenu && !_isDesktop
              ? () {
                  final box = context.findRenderObject()! as RenderBox;
                  final overlay = Overlay.of(context).context
                      .findRenderObject()! as RenderBox;
                  final position = box.localToGlobal(
                    Offset(box.size.width / 2, box.size.height / 2),
                    ancestor: overlay,
                  );
                  _openContextMenu(
                    context,
                    RelativeRect.fromSize(
                      position & Size.zero,
                      overlay.size,
                    ),
                  );
                }
              : null,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Avatar
                RoomAvatarWidget(room: room, size: 48),

                const SizedBox(width: 12),

                // Name + last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              room.getLocalizedDisplayname(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleMedium?.copyWith(
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          _CallIndicator(roomId: room.id),
                          if (memberships.length >= 2) ...[
                            const SizedBox(width: 6),
                            for (var j = 0;
                                j < memberships.length && j < 4;
                                j++)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _dotColor(j, cs),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      _buildSubtitle(context, prefs, lastEvent, cs, tt),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Timestamp + badge
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(lastEvent?.originServerTs),
                        style: tt.bodyMedium?.copyWith(
                          fontSize: 11,
                          color: unread > 0
                              ? cs.primary
                              : cs.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2,),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // On desktop, wrap in LongPressDraggable for reparenting.
    if (_isDesktop && parentSpaceId != null) {
      final dragData = RoomDragData(
        roomId: room.id,
        currentParentSpaceId: parentSpaceId,
      );
      tile = LongPressDraggable<ReparentDragData>(
        data: dragData,
        onDragStarted: () {
          context.read<SpaceReparentController>().startDrag(dragData);
        },
        onDragEnd: (_) {
          context.read<SpaceReparentController>().endDrag();
        },
        feedback: Material(
          color: Colors.transparent,
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoomAvatarWidget(room: room, size: 24),
                const SizedBox(width: 8),
                Text(
                  room.getLocalizedDisplayname(),
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: tile,
      );
    }

    if (_isDesktop && parentSpaceId != null && sectionRooms != null) {
      tile = _ReorderDragTarget(
        room: room,
        parentSpaceId: parentSpaceId!,
        sectionRooms: sectionRooms!,
        child: tile,
      );
    }

    return tile;
  }

  Widget _buildSubtitle(
    BuildContext context,
    PreferencesService prefs,
    Event? lastEvent,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final userId = context.read<MatrixService>().client.userID;
    final typers = room.typingUsers
        .where((u) => u.id != userId)
        .toList();
    if (typers.isNotEmpty && prefs.typingIndicators) {
      return Text(
        _typingPreview(typers),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(
          color: cs.primary,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Text(
      _lastMessagePreview(lastEvent, userId),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  String _typingPreview(List<User> typers) {
    return TypingIndicator.formatTypers(typers);
  }

  Color _dotColor(int index, ColorScheme cs) {
    final palette = [cs.primary, cs.tertiary, cs.secondary, cs.error];
    return palette[index % palette.length];
  }

  String _lastMessagePreview(Event? event, String? myUserId) {
    if (event == null) return 'No messages yet';
    if (event.type == kCallInvite) return 'Call in progress';
    if (event.type == kCallMember ||
        event.type == kCallMemberMsc ||
        event.body.contains(kCallMember) ||
        event.body.contains(kCallMemberMsc)) {
      return event.senderId == myUserId ? 'You initiated a call' : 'Call';
    }
    if (event.type == kCallHangup) {
      final reason = event.content.tryGet<String>('reason');
      if (reason == 'invite_timeout') return 'Missed call';
      return 'Call ended';
    }
    if (event.redacted) {
      final isMe = event.senderId == myUserId;
      if (isMe) return 'You deleted this message';
      final redactor = event.redactedBecause?.senderId;
      final isSelfRedact = redactor == event.senderId;
      if (isSelfRedact || redactor == null) return 'This message was deleted';
      final redactorUser =
          event.room.unsafeGetUserFromMemoryOrFallback(redactor);
      return 'Deleted by ${redactorUser.displayName ?? redactor}';
    }
    if (event.messageType == MessageTypes.BadEncrypted) {
      return '🔒 Unable to decrypt';
    }
    final body = stripReplyFallback(event.body);
    if (event.messageType == MessageTypes.Text) {
      return body;
    }
    if (event.messageType == MessageTypes.Image) return '📷 Image';
    if (event.messageType == MessageTypes.Video) return '🎬 Video';
    if (event.messageType == MessageTypes.File) return '📎 File';
    if (event.messageType == MessageTypes.Audio) return '🎵 Audio';
    return body;
  }

  String _formatTime(DateTime? ts) {
    if (ts == null) return '';
    final local = ts.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }
}

// ── Call indicator ────────────────────────────────────────────
class _CallIndicator extends StatelessWidget {
  const _CallIndicator({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final hasCall = context.select<CallService, bool>(
      (s) => s.roomHasActiveCall(roomId),
    );
    if (!hasCall) return const SizedBox.shrink();

    return const Padding(
      padding: EdgeInsets.only(left: 6),
      child: Icon(Icons.call_rounded, size: 14, color: Colors.green),
    );
  }
}

// ── Within-section reorder drag target ───────────────────────
class _ReorderDragTarget extends StatefulWidget {
  const _ReorderDragTarget({
    required this.room,
    required this.parentSpaceId,
    required this.sectionRooms,
    required this.child,
  });

  final Room room;
  final String parentSpaceId;
  final List<Room> sectionRooms;
  final Widget child;

  @override
  State<_ReorderDragTarget> createState() => _ReorderDragTargetState();
}

class _ReorderDragTargetState extends State<_ReorderDragTarget> {
  bool _showAbove = false;
  bool _showBelow = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DragTarget<ReparentDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is! RoomDragData) return false;
        if (data.currentParentSpaceId != widget.parentSpaceId) return false;
        if (data.roomId == widget.room.id) return false;
        return true;
      },
      onMove: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        final half = box.size.height / 2;
        setState(() {
          _showAbove = local.dy < half;
          _showBelow = local.dy >= half;
        });
      },
      onAcceptWithDetails: (details) {
        final insertAbove = _showAbove;
        setState(() {
          _showAbove = false;
          _showBelow = false;
        });
        final data = details.data;
        if (data is! RoomDragData) return;
        unawaited(_handleReorderDrop(context, data, insertAbove: insertAbove));
      },
      onLeave: (_) => setState(() {
        _showAbove = false;
        _showBelow = false;
      }),
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showAbove)
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: cs.primary,
              ),
            widget.child,
            if (_showBelow)
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: cs.primary,
              ),
          ],
        );
      },
    );
  }

  Future<void> _handleReorderDrop(
    BuildContext context,
    RoomDragData data, {
    required bool insertAbove,
  }) async {
    final matrix = context.read<MatrixService>();
    final space = matrix.client.getRoomById(widget.parentSpaceId);
    if (space == null) return;

    try {
      final rooms = widget.sectionRooms;
      final targetIndex = rooms.indexWhere((r) => r.id == widget.room.id);
      if (targetIndex < 0) return;

      final insertIndex = insertAbove ? targetIndex : targetIndex + 1;

      final orderMap = order_utils.buildOrderMap(space);

      final neighborBefore = insertIndex > 0
          ? orderMap[rooms[insertIndex - 1].id]
          : null;
      final neighborAfter = insertIndex < rooms.length
          ? orderMap[rooms[insertIndex].id]
          : null;

      final newOrder = order_utils.midpoint(neighborBefore, neighborAfter);
      if (newOrder == null) {
        debugPrint('[Lattice] Could not compute order midpoint for drag');
        return;
      }

      await space.setSpaceChild(data.roomId, order: newOrder);
      matrix.invalidateSpaceTree();
    } catch (e) {
      debugPrint('[Lattice] Drag reorder failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reorder: $e')),
        );
      }
    }
  }
}
