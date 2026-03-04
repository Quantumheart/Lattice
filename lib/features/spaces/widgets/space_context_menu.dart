import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/rooms/widgets/add_existing_rooms_dialog.dart';
import 'package:lattice/features/rooms/widgets/invite_user_dialog.dart';
import 'package:lattice/features/rooms/widgets/new_room_dialog.dart';

// ── Space Context Menu ──────────────────────────────────────────────

enum SpaceContextAction {
  markAsRead,
  invitePeople,
  spaceSettings,
  createRoom,
  createSubspace,
  addExistingRoom,
  notifications,
  leaveSpace,
}

Future<void> showSpaceContextMenu(
  BuildContext context,
  RelativeRect position,
  Room space,
) async {
  final cs = Theme.of(context).colorScheme;

  final canInvite = space.canInvite;
  final canManageChildren = space.canChangeStateEvent('m.space.child');
  final canEditName = space.canChangeStateEvent(EventTypes.RoomName);

  final action = await showMenu<SpaceContextAction>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      const PopupMenuItem(
        value: SpaceContextAction.markAsRead,
        child: Row(
          children: [
            Icon(Icons.done_all_rounded, size: 18),
            SizedBox(width: 8),
            Text('Mark as read'),
          ],
        ),
      ),
      if (canInvite)
        const PopupMenuItem(
          value: SpaceContextAction.invitePeople,
          child: Row(
            children: [
              Icon(Icons.person_add_outlined, size: 18),
              SizedBox(width: 8),
              Text('Invite people'),
            ],
          ),
        ),
      if (canEditName)
        const PopupMenuItem(
          value: SpaceContextAction.spaceSettings,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18),
              SizedBox(width: 8),
              Text('Space settings'),
            ],
          ),
        ),
      if (canManageChildren) ...[
        const PopupMenuItem(
          value: SpaceContextAction.createRoom,
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 18),
              SizedBox(width: 8),
              Text('Create room'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: SpaceContextAction.createSubspace,
          enabled: false,
          child: Row(
            children: [
              Icon(Icons.workspaces_outlined, size: 18),
              SizedBox(width: 8),
              Text('Create subspace'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: SpaceContextAction.addExistingRoom,
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18),
              SizedBox(width: 8),
              Text('Add existing room'),
            ],
          ),
        ),
      ],
      const PopupMenuItem(
        value: SpaceContextAction.notifications,
        enabled: false,
        child: Row(
          children: [
            Icon(Icons.notifications_outlined, size: 18),
            SizedBox(width: 8),
            Text('Notifications'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: SpaceContextAction.leaveSpace,
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Text('Leave space', style: TextStyle(color: cs.error)),
          ],
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case SpaceContextAction.markAsRead:
      await _handleMarkAsRead(space);
    case SpaceContextAction.invitePeople:
      if (context.mounted) await _handleInvite(context, space);
    case SpaceContextAction.leaveSpace:
      if (context.mounted) await _handleLeave(context, space);
    case SpaceContextAction.addExistingRoom:
      if (context.mounted) {
        final matrix = context.read<MatrixService>();
        await AddExistingRoomsDialog.show(
          context,
          space: space,
          matrixService: matrix,
        );
      }
    case SpaceContextAction.createRoom:
      if (context.mounted) {
        final matrix = context.read<MatrixService>();
        await NewRoomDialog.show(
          context,
          matrixService: matrix,
          parentSpaceIds: {space.id},
        );
      }
    case SpaceContextAction.spaceSettings:
      if (context.mounted) {
        context.goNamed(
          Routes.spaceDetails,
          pathParameters: {'spaceId': space.id},
        );
      }
    case SpaceContextAction.createSubspace:
    case SpaceContextAction.notifications:
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coming soon')),
        );
      }
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

/// Shows a leave-space confirmation dialog with an option to also leave
/// all child rooms. Reused by [SpaceDetailsPanel].
Future<void> handleLeaveSpace(BuildContext context, Room space) =>
    _handleLeave(context, space);

Future<void> _handleMarkAsRead(Room space) async {
  // Mark the space itself as read.
  final eventId = space.lastEvent?.eventId;
  if (eventId != null) {
    try {
      await space.setReadMarker(eventId);
    } catch (e) {
      debugPrint('[Lattice] Failed to mark space as read: $e');
    }
  }

  // Also mark all descendant non-space rooms as read.
  final descendantIds = <String>{};
  _collectDescendantRooms(space, descendantIds, space.client);

  final roomsToMark = <({Room room, String eventId})>[];
  for (final roomId in descendantIds) {
    final room = space.client.getRoomById(roomId);
    if (room == null || room.isSpace) continue;
    final childEventId = room.lastEvent?.eventId;
    if (childEventId == null) continue;
    roomsToMark.add((room: room, eventId: childEventId));
  }

  const batchSize = 5;
  for (var i = 0; i < roomsToMark.length; i += batchSize) {
    final batch = roomsToMark.sublist(i, min(i + batchSize, roomsToMark.length));
    await Future.wait(batch.map((r) => r.room.setReadMarker(r.eventId).catchError((e) {
      debugPrint('[Lattice] Failed to mark room ${r.room.id} as read: $e');
    })));
  }
}

Future<void> _handleInvite(BuildContext context, Room space) async {
  final mxid = await InviteUserDialog.show(context, room: space);

  if (mxid == null || !context.mounted) return;

  try {
    await space.invite(mxid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invited $mxid')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to invite: $e')),
      );
    }
  }
}

Future<void> _handleLeave(BuildContext context, Room space) async {
  final cs = Theme.of(context).colorScheme;
  final result = await showDialog<({bool confirmed, bool leaveChildren})>(
    context: context,
    builder: (ctx) {
      var leaveChildren = false;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Leave space?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You will leave "${space.getLocalizedDisplayname()}".'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: leaveChildren,
                onChanged: (v) => setState(() => leaveChildren = v ?? false),
                title: const Text('Also leave all rooms in this space'),
                subtitle: const Text(
                  'Rooms you stay in will move to your general room list.',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(
                ctx,
                (confirmed: true, leaveChildren: leaveChildren),
              ),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
    },
  );

  if (result == null || !result.confirmed || !context.mounted) return;

  try {
    final matrix = context.read<MatrixService>();

    // Collect child room IDs before leaving (recursive through subspaces).
    final childRoomIds = <String>{};
    if (result.leaveChildren) {
      _collectDescendantRooms(space, childRoomIds, matrix.client);
    }

    await space.leave();
    matrix.clearSpaceSelection();

    // Leave child rooms if requested.
    var failCount = 0;
    for (final roomId in childRoomIds) {
      final room = matrix.client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) continue;
      try {
        await room.leave();
      } catch (_) {
        failCount++;
      }
    }
    if (failCount > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave $failCount room(s)')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to leave space: $e')),
      );
    }
  }
}

void _collectDescendantRooms(Room space, Set<String> ids, Client client) {
  for (final child in space.spaceChildren) {
    final childId = child.roomId;
    if (childId == null) continue;
    if (ids.contains(childId)) continue;
    final childRoom = client.getRoomById(childId);
    if (childRoom == null || childRoom.membership != Membership.join) continue;
    ids.add(childId);
    if (childRoom.isSpace) {
      _collectDescendantRooms(childRoom, ids, client);
    }
  }
}

