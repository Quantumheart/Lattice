import 'package:flutter/material.dart';

import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'new_room_dialog.dart';
import 'room_list_models.dart';

// ── Section header ──────────────────────────────────────────
class RoomSectionHeader extends StatelessWidget {
  const RoomSectionHeader({
    super.key,
    required this.item,
    required this.prefs,
    required this.matrix,
  });

  final HeaderItem item;
  final PreferencesService prefs;
  final MatrixService matrix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCollapsed =
        prefs.collapsedSpaceSections.contains(item.sectionKey);

    final canAddRoom = item.isSpace &&
        (matrix.client.getRoomById(item.sectionKey)
                ?.canChangeStateEvent('m.space.child') ??
            false);

    return Padding(
      padding: EdgeInsets.only(
        left: 10.0 + item.depth * 16.0,
        right: 10,
        top: 8,
        bottom: 2,
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
              if (canAddRoom)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  iconSize: 18,
                  icon: Icon(
                    Icons.add_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: 'Add room',
                  onPressed: () => NewRoomDialog.show(
                    context,
                    matrixService: matrix,
                    parentSpaceIds: {item.sectionKey},
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
    );
  }
}
