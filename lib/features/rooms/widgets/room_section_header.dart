import 'package:flutter/material.dart';

import 'package:lattice/core/services/preferences_service.dart';
import 'room_list_models.dart';

// ── Section header ──────────────────────────────────────────
class RoomSectionHeader extends StatelessWidget {
  const RoomSectionHeader({
    super.key,
    required this.item,
    required this.prefs,
  });

  final HeaderItem item;
  final PreferencesService prefs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCollapsed =
        prefs.collapsedSpaceSections.contains(item.sectionKey);

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
