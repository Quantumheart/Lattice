import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/settings_screen.dart';
import '../services/client_manager.dart';
import '../services/matrix_service.dart';
import '../services/preferences_service.dart';

/// A vertical icon rail showing the user's Matrix spaces.
/// Modelled after Discord / Slack's sidebar.
class SpaceRail extends StatelessWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    // Keep space ordering in sync with persisted preference.
    matrix.updateSpaceOrder(prefs.spaceOrder);

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
            isSelected: matrix.selectedSpaceIds.isEmpty,
            color: cs.primary,
            onTap: () => matrix.clearSpaceSelection(),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1, color: cs.outlineVariant),
          ),

          // Spaces (drag-to-reorder)
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: spaces.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final ids = spaces.map((s) => s.id).toList();
                final id = ids.removeAt(oldIndex);
                ids.insert(newIndex, id);
                prefs.setSpaceOrder(ids);
                matrix.updateSpaceOrder(ids);
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) => Material(
                    color: Colors.transparent,
                    elevation: 4,
                    child: child,
                  ),
                  child: child,
                );
              },
              itemBuilder: (context, i) {
                final space = spaces[i];
                final childCount = space.spaceChildren.length;
                final unread = matrix.unreadCountForSpace(space.id);
                return ReorderableDragStartListener(
                  key: ValueKey(space.id),
                  index: i,
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onSecondaryTapUp: (details) {
                      _showContextMenu(
                          context, details.globalPosition, space.id);
                    },
                    child: _RailIcon(
                      label: space.getLocalizedDisplayname().isNotEmpty
                          ? space.getLocalizedDisplayname()[0].toUpperCase()
                          : '?',
                      tooltip:
                          '${space.getLocalizedDisplayname()} \u00b7 $childCount rooms',
                      isSelected:
                          matrix.selectedSpaceIds.contains(space.id),
                      avatarUrl: space.avatar?.toString(),
                      color: _spaceColor(i, cs),
                      unreadCount: unread,
                      onTap: () {
                        final keys =
                            HardwareKeyboard.instance.logicalKeysPressed;
                        final isModifier = keys.contains(
                                LogicalKeyboardKey.controlLeft) ||
                            keys.contains(LogicalKeyboardKey.controlRight) ||
                            keys.contains(LogicalKeyboardKey.metaLeft) ||
                            keys.contains(LogicalKeyboardKey.metaRight);
                        if (isModifier) {
                          matrix.toggleSpaceSelection(space.id);
                        } else {
                          matrix.selectSpace(space.id);
                        }
                      },
                      onLongPress: () =>
                          matrix.toggleSpaceSelection(space.id),
                    ),
                  ),
                  ),
                );
              },
            ),
          ),

          // Add space button
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
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

          // Account avatar + menu
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AccountButton(cs: cs),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, String spaceId) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: 'mute', child: Text('Mute space')),
        PopupMenuItem(value: 'leave', child: Text('Leave space')),
        PopupMenuItem(value: 'settings', child: Text('Space settings')),
      ],
    ).then((value) {
      // TODO: implement context menu actions
      if (value != null) {
        debugPrint('[Lattice] Space context menu: $value for $spaceId');
      }
    });
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
    this.unreadCount,
    this.onLongPress,
  });

  final String label;
  final String tooltip;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final String? avatarUrl;
  final bool outlined;
  final int? unreadCount;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget icon = Tooltip(
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
              mouseCursor: SystemMouseCursors.click,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: outlined ? 20 : 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Overlay unread badge
    if (unreadCount != null && unreadCount! > 0) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            top: -2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  unreadCount! > 99 ? '99+' : '$unreadCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: cs.onError,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return icon;
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ClientManager>();
    final matrix = context.watch<MatrixService>();
    final userId = matrix.client.userID;
    final initial = (userId != null && userId.length > 1)
        ? userId[1].toUpperCase()
        : (userId ?? '?')[0].toUpperCase();

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      offset: const Offset(64, 0),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.settings:
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          case _AccountAction.switchAccount:
            // Handled inline via index-based items.
            break;
        }
      },
      itemBuilder: (ctx) => [
        // Account entries (only show if multiple).
        if (manager.hasMultipleAccounts)
          for (var i = 0; i < manager.services.length; i++)
            PopupMenuItem<_AccountAction>(
              value: _AccountAction.switchAccount,
              enabled: i != manager.activeIndex,
              onTap: () => manager.setActiveAccount(i),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: i == manager.activeIndex
                        ? cs.primary
                        : cs.surfaceContainerHigh,
                    child: Text(
                      _initial(manager.services[i].client.userID),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i == manager.activeIndex
                            ? cs.onPrimary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      manager.services[i].client.userID ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (i == manager.activeIndex)
                    Icon(Icons.check, size: 18, color: cs.primary),
                ],
              ),
            ),
        if (manager.hasMultipleAccounts) const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountAction.settings,
          child: Row(
            children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 10),
              Text('Settings'),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: CircleAvatar(
          radius: 18,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  String _initial(String? userId) {
    if (userId != null && userId.length > 1) return userId[1].toUpperCase();
    return (userId ?? '?')[0].toUpperCase();
  }
}

enum _AccountAction { settings, switchAccount }
