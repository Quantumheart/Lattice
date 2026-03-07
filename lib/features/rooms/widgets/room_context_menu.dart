import 'package:flutter/material.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/utils/order_utils.dart' as order_utils;
import 'package:lattice/features/rooms/widgets/add_room_to_space_dialog.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

// ── Room Context Menu ───────────────────────────────────────────────

enum _RoomContextAction { addToSpace, removeFromSpace, moveUp, moveDown }

Future<void> showRoomContextMenu(
  BuildContext context,
  RelativeRect position,
  Room room, {
  String? parentSpaceId,
  List<Room>? sectionRooms,
}) async {
  final matrix = context.read<MatrixService>();
  final cs = Theme.of(context).colorScheme;

  final selectedIds = matrix.selectedSpaceIds;
  final memberships = matrix.spaceMemberships(room.id);

  Room? activeSpace;
  var canRemove = false;
  for (final spaceId in selectedIds) {
    final space = matrix.client.getRoomById(spaceId);
    if (space != null && space.canChangeStateEvent('m.space.child')) {
      activeSpace = space;
      canRemove = true;
      break;
    }
  }

  final canAdd = matrix.spaces.any((s) =>
      s.canChangeStateEvent('m.space.child') &&
      !memberships.contains(s.id),);

  Room? reorderSpace;
  List<Room>? orderedRooms;
  var roomIndex = -1;
  if (parentSpaceId != null && sectionRooms != null) {
    final space = matrix.client.getRoomById(parentSpaceId);
    if (space != null && space.canChangeStateEvent('m.space.child')) {
      reorderSpace = space;
      orderedRooms = sectionRooms;
      roomIndex = orderedRooms.indexWhere((r) => r.id == room.id);
    }
  }

  final canMoveUp = reorderSpace != null && roomIndex > 0;
  final canMoveDown =
      reorderSpace != null && orderedRooms != null && roomIndex >= 0 &&
      roomIndex < orderedRooms.length - 1;

  if (!canAdd && !canRemove && !canMoveUp && !canMoveDown) return;

  final action = await showMenu<_RoomContextAction>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      if (canMoveUp)
        const PopupMenuItem(
          value: _RoomContextAction.moveUp,
          child: Row(
            children: [
              Icon(Icons.arrow_upward_rounded, size: 18),
              SizedBox(width: 8),
              Text('Move up'),
            ],
          ),
        ),
      if (canMoveDown)
        const PopupMenuItem(
          value: _RoomContextAction.moveDown,
          child: Row(
            children: [
              Icon(Icons.arrow_downward_rounded, size: 18),
              SizedBox(width: 8),
              Text('Move down'),
            ],
          ),
        ),
      if (canAdd)
        const PopupMenuItem(
          value: _RoomContextAction.addToSpace,
          child: Row(
            children: [
              Icon(Icons.add_link_rounded, size: 18),
              SizedBox(width: 8),
              Text('Add to space'),
            ],
          ),
        ),
      if (canRemove)
        PopupMenuItem(
          value: _RoomContextAction.removeFromSpace,
          child: Row(
            children: [
              Icon(Icons.link_off_rounded, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Remove from ${activeSpace!.getLocalizedDisplayname()}',
                  style: TextStyle(color: cs.error),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case _RoomContextAction.addToSpace:
      await AddRoomToSpaceDialog.show(
        context,
        room: room,
        matrixService: matrix,
      );
    case _RoomContextAction.removeFromSpace:
      if (activeSpace != null) {
        await _handleRemoveFromSpace(context, activeSpace, room);
      }
    case _RoomContextAction.moveUp:
      if (reorderSpace != null && orderedRooms != null && roomIndex > 0) {
        await _handleReorder(
          context, reorderSpace, orderedRooms, roomIndex, roomIndex - 1,);
      }
    case _RoomContextAction.moveDown:
      if (reorderSpace != null && orderedRooms != null &&
          roomIndex < orderedRooms.length - 1) {
        await _handleReorder(
          context, reorderSpace, orderedRooms, roomIndex, roomIndex + 1,);
      }
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

Future<void> _handleReorder(
  BuildContext context,
  Room space,
  List<Room> orderedRooms,
  int fromIndex,
  int toIndex,
) async {
  try {
    final matrix = context.read<MatrixService>();
    final roomId = orderedRooms[fromIndex].id;

    final orderMap = order_utils.buildOrderMap(space);

    final String? neighborBefore;
    final String? neighborAfter;
    if (toIndex < fromIndex) {
      neighborBefore = toIndex > 0 ? orderMap[orderedRooms[toIndex - 1].id] : null;
      neighborAfter = orderMap[orderedRooms[toIndex].id];
    } else {
      neighborBefore = orderMap[orderedRooms[toIndex].id];
      neighborAfter = toIndex + 1 < orderedRooms.length
          ? orderMap[orderedRooms[toIndex + 1].id]
          : null;
    }

    final newOrder = order_utils.midpoint(neighborBefore, neighborAfter);
    if (newOrder == null) {
      debugPrint('[Lattice] Could not compute order midpoint');
      return;
    }

    await space.setSpaceChild(roomId, order: newOrder);
    matrix.invalidateSpaceTree();
  } catch (e) {
    debugPrint('[Lattice] Reorder failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reorder: $e')),
      );
    }
  }
}

Future<void> _handleRemoveFromSpace(
  BuildContext context,
  Room space,
  Room room,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove from space?'),
      content: Text(
        'Remove "${room.getLocalizedDisplayname()}" from '
        '"${space.getLocalizedDisplayname()}"? The room won\'t be deleted, '
        'just unlinked from the space.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    final matrix = context.read<MatrixService>();
    await space.removeSpaceChild(room.id);
    matrix.invalidateSpaceTree();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove room: $e')),
      );
    }
  }
}
