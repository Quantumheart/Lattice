import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';

// ── Room Context Menu ───────────────────────────────────────────────

Future<void> showRoomContextMenu(
  BuildContext context,
  RelativeRect position,
  Room room,
) async {
  final matrix = context.read<MatrixService>();
  final cs = Theme.of(context).colorScheme;

  // Determine the active space (if any) and permissions.
  final selectedIds = matrix.selectedSpaceIds;
  if (selectedIds.isEmpty) return;

  final spaceId = selectedIds.first;
  final space = matrix.client.getRoomById(spaceId);
  if (space == null) return;

  final canManageChildren = space.canChangeStateEvent('m.space.child');
  if (!canManageChildren) return;

  final action = await showMenu<String>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      PopupMenuItem(
        value: 'remove_from_space',
        child: Row(
          children: [
            Icon(Icons.link_off_rounded, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Text('Remove from space', style: TextStyle(color: cs.error)),
          ],
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case 'remove_from_space':
      await _handleRemoveFromSpace(context, space, room);
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

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
