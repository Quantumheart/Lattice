import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/core/utils/reply_fallback.dart';
import 'package:lattice/core/utils/time_format.dart';
import 'package:lattice/features/notifications/models/notification_constants.dart';
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
    final selection = context.watch<SelectionService>();
    final inviteCount =
        selection.invitedRooms.length + selection.invitedSpaces.length;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(InboxText.title),
      ),
      body: Column(
        children: [
          // ── Filter segmented button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<InboxFilter>(
              showSelectedIcon: false,
              selected: {controller.filter},
              onSelectionChanged: (selected) =>
                  controller.setFilter(selected.first),
              segments: [
                const ButtonSegment(
                  value: InboxFilter.all,
                  label: Text(InboxText.filterAll),
                ),
                const ButtonSegment(
                  value: InboxFilter.mentions,
                  label: Text(InboxText.filterMentions),
                ),
                ButtonSegment(
                  value: InboxFilter.invitations,
                  label: Text(
                    inviteCount > 0
                        ? InboxText.invitationsWithCount(inviteCount)
                        : InboxText.filterInvitations,
                  ),
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
                                  InboxText.failedToLoad,
                                  style: tt.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  onPressed: controller.fetch,
                                  child: const Text(InboxText.retry),
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
                                      InboxText.noNotifications,
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
                    tooltip: InboxText.tooltipMarkAsRead,
                    onPressed: () => controller.markRoomAsRead(group.roomId),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    tooltip: InboxText.tooltipOpen,
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

    final body = _extractBody(context, event);
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

  String _extractBody(BuildContext context, matrix_sdk.MatrixEvent event) {
    final controller = context.read<InboxController>();
    final content =
        controller.decryptedContentFor(event.eventId) ?? event.content;
    final msgtype = content['msgtype'];

    if (msgtype == matrix_sdk.MessageTypes.Image) return InboxText.mediaImage;
    if (msgtype == matrix_sdk.MessageTypes.Video) return InboxText.mediaVideo;
    if (msgtype == matrix_sdk.MessageTypes.Audio) return InboxText.mediaAudio;
    if (msgtype == matrix_sdk.MessageTypes.File) return InboxText.mediaFile;

    final body = content['body'];
    if (body is String) return stripReplyFallback(body);

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
    final selection = context.watch<SelectionService>();
    final invitedRooms = selection.invitedRooms;
    final invitedSpaces = selection.invitedSpaces;

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
              InboxText.noPendingInvitations,
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
              InboxText.sectionSpaces,
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
              InboxText.sectionRooms,
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
                child: const Text(InboxText.loadMore),
              ),
      ),
    );
  }
}
