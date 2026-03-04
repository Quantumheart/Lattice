import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/notification_filter.dart';
import 'package:lattice/core/utils/reply_fallback.dart';
import 'package:lattice/features/chat/widgets/typing_indicator.dart' show TypingIndicator;
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'room_context_menu.dart';

// ── Room tile ───────────────────────────────────────────────
class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    required this.isSelected,
    required this.memberships,
    required this.hasContextMenu,
  });

  final Room room;
  final bool isSelected;
  final Set<String> memberships;
  final bool hasContextMenu;

  void _openContextMenu(BuildContext context, RelativeRect position) {
    if (!hasContextMenu) return;
    showRoomContextMenu(context, position, room);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final unread = effectiveUnreadCount(room, prefs);
    final lastEvent = room.lastEvent;
    final hasMenu = hasContextMenu;

    return Padding(
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
          onLongPress: hasMenu
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
                          // Multi-space membership dots
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
                              horizontal: 6, vertical: 2),
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
