import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/utils/reply_fallback.dart';
import 'package:lattice/core/utils/time_format.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:lattice/features/rooms/widgets/invite_tile.dart';
import 'package:lattice/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:provider/provider.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final InboxController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<InboxController>();
    if (_controller.grouped.isEmpty && !_controller.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_controller.fetch());
      });
    }
    _controller.startPolling();
  }

  @override
  void dispose() {
    _controller.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InboxController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
      ),
      body: Column(
        children: [
          // ── Filter chips ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: controller.filter == InboxFilter.all,
                  onSelected: (_) => controller.setFilter(InboxFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Mentions'),
                  selected: controller.filter == InboxFilter.mentions,
                  onSelected: (_) => controller.setFilter(InboxFilter.mentions),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    controller.invitationCount > 0
                        ? 'Invitations (${controller.invitationCount})'
                        : 'Invitations',
                  ),
                  selected: controller.filter == InboxFilter.invitations,
                  onSelected: (_) =>
                      controller.setFilter(InboxFilter.invitations),
                ),
              ],
            ),
          ),

          // ── Content ──
          Expanded(
            child: controller.filter == InboxFilter.invitations
                ? _InvitationsView(cs: cs, tt: tt)
                : controller.isLoading && controller.grouped.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : controller.error != null && controller.grouped.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 48,
                                    color: cs.error.withValues(alpha: 0.6),),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to load notifications',
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  onPressed: controller.fetch,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : controller.grouped.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications_none_rounded,
                                        size: 56,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.3),),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No notifications',
                                      style: tt.titleMedium?.copyWith(
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: controller.fetch,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4,),
                                  itemCount: controller.grouped.length +
                                      (controller.hasMore ? 1 : 0),
                                  itemBuilder: (context, i) {
                                    if (i == controller.grouped.length) {
                                      return _LoadMoreButton(
                                        isLoading: controller.isLoading,
                                        onPressed: controller.loadMore,
                                      );
                                    }
                                    return _NotificationGroupTile(
                                      group: controller.grouped[i],
                                      controller: controller,
                                    );
                                  },
                                ),
                              ),
          ),
        ],
      ),
    );
  }
}

// ── Notification group tile ──────────────────────────────────
class _NotificationGroupTile extends StatelessWidget {
  const _NotificationGroupTile({
    required this.group,
    required this.controller,
  });

  final NotificationGroup group;
  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = controller.client;
    final room = client.getRoomById(group.roomId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Group header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  if (room != null) ...[
                    RoomAvatarWidget(room: room, size: 32),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      group.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    tooltip: 'Mark as read',
                    onPressed: () => controller.markRoomAsRead(group.roomId),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    tooltip: 'Open',
                    onPressed: () => context.goNamed(
                      Routes.room,
                      pathParameters: {'roomId': group.roomId},
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Individual notifications ──
            for (final notification in group.notifications)
              _NotificationTile(
                notification: notification,
                client: client,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Individual notification tile ─────────────────────────────
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.client,
  });

  final matrix_sdk.Notification notification;
  final matrix_sdk.Client client;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final event = notification.event;

    final senderId = event.senderId;
    final room = client.getRoomById(notification.roomId);
    final senderName =
        room?.unsafeGetUserFromMemoryOrFallback(senderId).calcDisplayname() ??
            senderId;

    final body = _extractBody(event);
    final ts = DateTime.fromMillisecondsSinceEpoch(notification.ts);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unread indicator
          if (!notification.read)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      formatRelativeTimestamp(ts),
                      style: tt.bodySmall?.copyWith(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _extractBody(matrix_sdk.MatrixEvent event) {
    final content = event.content;
    final msgtype = content['msgtype'];

    // Check media types first — their body is just a filename.
    if (msgtype == matrix_sdk.MessageTypes.Image) return '📷 Image';
    if (msgtype == matrix_sdk.MessageTypes.Video) return '🎥 Video';
    if (msgtype == matrix_sdk.MessageTypes.Audio) return '🎵 Audio';
    if (msgtype == matrix_sdk.MessageTypes.File) return '📎 File';

    final body = content['body'];
    if (body is String) return stripReplyFallback(body);

    // Fallback for state events, etc.
    return '';
  }
}

// ── Invitations view ──────────────────────────────────────────
class _InvitationsView extends StatelessWidget {
  const _InvitationsView({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final invitedRooms = matrix.invitedRooms;
    final invitedSpaces = matrix.invitedSpaces;

    if (invitedRooms.isEmpty && invitedSpaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded,
                size: 56,
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),),
            const SizedBox(height: 16),
            Text(
              'No pending invitations',
              style: tt.titleMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [
        if (invitedSpaces.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              'Spaces',
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final space in invitedSpaces) InviteTile(room: space),
        ],
        if (invitedRooms.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              'Rooms',
              style: tt.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final room in invitedRooms) InviteTile(room: room),
        ],
      ],
    );
  }
}

// ── Load more button ─────────────────────────────────────────
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : TextButton(
                onPressed: onPressed,
                child: const Text('Load more'),
              ),
      ),
    );
  }
}
