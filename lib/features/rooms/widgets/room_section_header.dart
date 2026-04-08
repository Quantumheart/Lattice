import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/services/sub_services/selection_service.dart';
import 'package:lattice/features/rooms/widgets/new_room_dialog.dart';
import 'package:lattice/features/rooms/widgets/room_list_models.dart';
import 'package:lattice/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:lattice/features/spaces/widgets/space_reparent_controller.dart';
import 'package:provider/provider.dart';

// ── Popup menu actions ──────────────────────────────────────
enum _HeaderAddAction { createRoom, createSubspace }

// ── Section header ──────────────────────────────────────────
class RoomSectionHeader extends StatelessWidget {
  const RoomSectionHeader({
    required this.item, required this.prefs, required this.selection, required this.matrixService, super.key,
  });

  final HeaderItem item;
  final PreferencesService prefs;
  final SelectionService selection;
  final MatrixService matrixService;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCollapsed =
        prefs.collapsedSpaceSections.contains(item.sectionKey);

    final spaceRoom = matrixService.client.getRoomById(item.sectionKey);
    final canManageChildren = item.isSpace &&
        (spaceRoom?.canChangeStateEvent('m.space.child') ?? false);

    final reparent = context.watch<SpaceReparentController>();
    final isHovered = reparent.hoveredHeaderId == item.sectionKey;

    final Widget header = Padding(
      padding: EdgeInsets.only(
        left: 10.0 + item.depth * 16.0,
        right: 10,
        top: 8,
        bottom: 2,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isHovered ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => prefs.toggleSectionCollapsed(item.sectionKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  isCollapsed
                      ? Icons.chevron_right
                      : Icons.expand_more,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.name.toUpperCase(),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canManageChildren)
                  Builder(
                    builder: (btnContext) => IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      iconSize: 18,
                      icon: Icon(
                        Icons.add_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: 'Add to space',
                      onPressed: () => _showAddMenu(btnContext),
                    ),
                  ),
                Text(
                  '${item.roomCount}',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap in DragTarget only for space sections.
    if (!item.isSpace) return header;

    Widget result = DragTarget<ReparentDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (!canManageChildren) return false;

        if (data is SpaceDragData) {
          // Reject dropping a space onto itself or its own descendant.
          if (wouldCreateCycle(
              selection.spaceTree, item.sectionKey, data.spaceId,)) {
            return false;
          }
        }

        reparent.setHoveredHeader(item.sectionKey);
        return true;
      },
      onAcceptWithDetails: (details) {
        reparent.setHoveredHeader(null);
        unawaited(_handleDrop(context, details.data));
      },
      onLeave: (_) => reparent.setHoveredHeader(null),
      builder: (context, candidateData, rejectedData) => header,
    );

    // Make subspace headers draggable for reparenting.
    if (item.depth > 0) {
      final dragData = SpaceDragData(spaceId: item.sectionKey);
      result = LongPressDraggable<ReparentDragData>(
        data: dragData,
        onDragStarted: () => reparent.startDrag(dragData),
        onDragEnd: (_) => reparent.endDrag(),
        feedback: Material(
          color: Colors.transparent,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspaces_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  item.name,
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: header),
        child: result,
      );
    }

    return result;
  }

  void _showAddMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final cs = Theme.of(context).colorScheme;

    unawaited(showMenu<_HeaderAddAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height,
        pos.dx + box.size.width,
        pos.dy + box.size.height,
      ),
      color: cs.surfaceContainer,
      items: [
        const PopupMenuItem(
          value: _HeaderAddAction.createRoom,
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 18),
              SizedBox(width: 8),
              Text('Create room'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _HeaderAddAction.createSubspace,
          child: Row(
            children: [
              Icon(Icons.workspaces_outlined, size: 18),
              SizedBox(width: 8),
              Text('Create subspace'),
            ],
          ),
        ),
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      switch (action) {
        case _HeaderAddAction.createRoom:
          unawaited(NewRoomDialog.show(
            context,
            matrixService: matrixService,
            parentSpaceIds: {item.sectionKey},
          ),);
        case _HeaderAddAction.createSubspace:
          final spaceRoom = matrixService.client.getRoomById(item.sectionKey);
          if (spaceRoom != null) {
            unawaited(CreateSubspaceDialog.show(
              context,
              matrixService: matrixService,
              parentSpace: spaceRoom,
            ),);
          }
      }
    },),);
  }

  Future<void> _handleDrop(BuildContext context, ReparentDragData data) async {
    final targetRoom = matrixService.client.getRoomById(item.sectionKey);
    if (targetRoom == null) return;

    try {
      switch (data) {
        case SpaceDragData(:final spaceId):
          // Find old parent by scanning spaces for one whose children contain
          // the dragged space.
          String? oldParentId;
          for (final space in selection.spaces) {
            if (space.spaceChildren.any((c) => c.roomId == spaceId)) {
              oldParentId = space.id;
              break;
            }
          }

          await targetRoom.setSpaceChild(spaceId);
          if (oldParentId != null && oldParentId != item.sectionKey) {
            final oldParent = matrixService.client.getRoomById(oldParentId);
            await oldParent?.removeSpaceChild(spaceId);
          }

        case RoomDragData(:final roomId, :final currentParentSpaceId):
          await targetRoom.setSpaceChild(roomId);
          if (currentParentSpaceId != null &&
              currentParentSpaceId != item.sectionKey) {
            final oldParent =
                matrixService.client.getRoomById(currentParentSpaceId);
            await oldParent?.removeSpaceChild(roomId);
          }
      }

      selection.invalidateSpaceTree();
    } catch (e) {
      debugPrint('[Lattice] Reparent failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move: $e')),
        );
      }
    }
  }
}
