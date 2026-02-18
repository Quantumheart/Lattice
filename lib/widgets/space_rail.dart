import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';

/// A vertical icon rail showing the user's Matrix spaces.
/// Modelled after Discord / Slack's sidebar.
class SpaceRail extends StatelessWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final spaces = matrix.spaces;

    return Container(
      width: 64,
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Home (all rooms)
          _RailIcon(
            label: 'H',
            tooltip: 'Home',
            isSelected: matrix.selectedSpaceId == null,
            color: cs.primary,
            onTap: () => matrix.selectSpace(null),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1, color: cs.outlineVariant),
          ),

          // Spaces
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: spaces.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final space = spaces[i];
                return _RailIcon(
                  label: space.getLocalizedDisplayname().isNotEmpty
                      ? space.getLocalizedDisplayname()[0].toUpperCase()
                      : '?',
                  tooltip: space.getLocalizedDisplayname(),
                  isSelected: matrix.selectedSpaceId == space.id,
                  avatarUrl: space.avatar?.toString(),
                  color: _spaceColor(i, cs),
                  onTap: () {
                    matrix.selectSpace(
                      matrix.selectedSpaceId == space.id ? null : space.id,
                    );
                  },
                );
              },
            ),
          ),

          // Add space button
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RailIcon(
              label: '+',
              tooltip: 'Join or create a space',
              isSelected: false,
              color: cs.outlineVariant,
              outlined: true,
              onTap: () {
                // TODO: join/create space dialog
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _spaceColor(int index, ColorScheme cs) {
    final palette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
    ];
    return palette[index % palette.length];
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.label,
    required this.tooltip,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.avatarUrl,
    this.outlined = false,
  });

  final String label;
  final String tooltip;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final String? avatarUrl;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: isSelected ? 48 : 44,
          height: isSelected ? 48 : 44,
          decoration: BoxDecoration(
            color: outlined
                ? Colors.transparent
                : isSelected
                    ? color
                    : cs.surfaceContainerHigh,
            borderRadius:
                BorderRadius.circular(isSelected ? 14 : 22),
            border: outlined
                ? Border.all(
                    color: cs.outlineVariant,
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(isSelected ? 14 : 22),
              onTap: onTap,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: outlined ? 20 : 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? cs.onPrimary
                        : outlined
                            ? cs.onSurfaceVariant
                            : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
