import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/client_manager.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/utils/media_auth.dart';
import 'package:lattice/features/notifications/services/inbox_controller.dart';
import 'package:lattice/features/rooms/widgets/invite_dialog.dart';
import 'package:lattice/features/spaces/widgets/space_action_dialog.dart';
import 'package:lattice/features/spaces/widgets/space_context_menu.dart';
import 'package:lattice/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

/// A vertical icon rail showing the user's Matrix spaces.
/// Modelled after Discord / Slack's sidebar.
class SpaceRail extends StatefulWidget {
  const SpaceRail({super.key});

  @override
  State<SpaceRail> createState() => _SpaceRailState();
}

class _SpaceRailState extends State<SpaceRail> {
  bool _orderSynced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_orderSynced) {
      _orderSynced = true;
      final matrix = context.read<MatrixService>();
      final prefs = context.read<PreferencesService>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) matrix.updateSpaceOrder(prefs.spaceOrder);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final spaces = matrix.topLevelSpaces;

    final inboxUnread = context.select<InboxController, int>((c) => c.unreadCount);

    return Container(
      width: 64,
      color: Theme.of(context).brightness == Brightness.light
          ? cs.surfaceContainerLow
          : cs.surfaceContainerHigh,
      child: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 12),

          // Home (all rooms)
          _RailIcon(
            label: 'H',
            tooltip: 'Home',
            isSelected: matrix.selectedSpaceIds.isEmpty,
            color: cs.primary,
            onTap: matrix.clearSpaceSelection,
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
                unawaited(context.read<PreferencesService>().setSpaceOrder(ids));
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
                    child: Builder(
                      builder: (iconContext) {
                        final displayName = space.getLocalizedDisplayname();
                        return _RailIcon(
                        label: displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        tooltip:
                            '$displayName \u00b7 $childCount rooms',
                        isSelected:
                            matrix.selectedSpaceIds.contains(space.id),
                        room: space,
                        color: _spaceColor(i, cs),
                        unreadCount: unread,
                        onTap: () {
                          final keys =
                              HardwareKeyboard.instance.logicalKeysPressed;
                          final isModifier = keys.contains(
                                  LogicalKeyboardKey.controlLeft,) ||
                              keys.contains(LogicalKeyboardKey.controlRight) ||
                              keys.contains(LogicalKeyboardKey.metaLeft) ||
                              keys.contains(LogicalKeyboardKey.metaRight);
                          if (isModifier) {
                            matrix.toggleSpaceSelection(space.id);
                          } else {
                            matrix.selectSpace(space.id);
                          }
                        },
                        onLongPress: () {
                          final box =
                              iconContext.findRenderObject()! as RenderBox;
                          final pos = box.localToGlobal(Offset.zero);
                          unawaited(showSpaceContextMenu(
                            iconContext,
                            RelativeRect.fromLTRB(
                              pos.dx + box.size.width,
                              pos.dy,
                              pos.dx + box.size.width,
                              pos.dy + box.size.height,
                            ),
                            space,
                          ),);
                        },
                        onSecondaryTapUp: (details) {
                          final box =
                              iconContext.findRenderObject()! as RenderBox;
                          final pos = box.localToGlobal(Offset.zero);
                          unawaited(showSpaceContextMenu(
                            iconContext,
                            RelativeRect.fromLTRB(
                              pos.dx + box.size.width,
                              details.globalPosition.dy,
                              pos.dx + box.size.width,
                              details.globalPosition.dy,
                            ),
                            space,
                          ),);
                        },
                      );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // Add space button (after spaces list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Builder(
              builder: (btnContext) => _RailIcon(
                label: '+',
                tooltip: 'Join or create a space',
                isSelected: false,
                color: cs.outlineVariant,
                outlined: true,
                onTap: () {
                  final box = btnContext.findRenderObject()! as RenderBox;
                  final position = box.localToGlobal(Offset.zero);
                  unawaited(showSpaceActionMenu(
                    btnContext,
                    RelativeRect.fromLTRB(
                      position.dx + box.size.width,
                      position.dy,
                      position.dx + box.size.width,
                      position.dy + box.size.height,
                    ),
                  ),);
                },
              ),
            ),
          ),

          // Invited spaces (non-reorderable, scrollable)
          Builder(builder: (_) {
            final invited = matrix.invitedSpaces;
            if (invited.isEmpty) return const SizedBox.shrink();
            return Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4,),
                    child: Divider(height: 1, color: cs.outlineVariant),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final space in invited)
                          Builder(builder: (_) {
                            final name = space.getLocalizedDisplayname();
                            return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Opacity(
                              opacity: 0.7,
                              child: _RailIcon(
                                label: name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                tooltip: 'Invited: $name',
                                isSelected: false,
                                color: cs.outlineVariant,
                                outlined: true,
                                onTap: () async {
                                  final result = await InviteDialog.show(
                                    context,
                                    room: space,
                                  );
                                  if (result == true && mounted) {
                                    matrix.selectSpace(space.id);
                                  }
                                },
                              ),
                            ),
                          );
                          },),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },),

          // Divider + Inbox icon with badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Divider(height: 1, color: cs.outlineVariant),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RailIcon(
              icon: Icons.inbox_rounded,
              label: '!',
              tooltip: 'Inbox',
              isSelected: false,
              color: cs.outlineVariant,
              outlined: true,
              unreadCount: inboxUnread > 0 ? inboxUnread : null,
              onTap: () => context.goNamed(Routes.inbox),
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

class _RailIcon extends StatefulWidget {
  const _RailIcon({
    required this.label,
    required this.tooltip,
    required this.isSelected,
    required this.color,
    required this.onTap,
    this.icon,
    this.room,
    this.outlined = false,
    this.unreadCount,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  final IconData? icon;
  final String label;
  final String tooltip;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  final Room? room;
  final bool outlined;
  final int? unreadCount;
  final VoidCallback? onLongPress;
  final void Function(TapUpDetails)? onSecondaryTapUp;

  @override
  State<_RailIcon> createState() => _RailIconState();
}

class _RailIconState extends State<_RailIcon> {
  String? _resolvedUrl;
  Uri? _lastAvatarUri;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveThumbnail());
  }

  @override
  void didUpdateWidget(_RailIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.room?.avatar != _lastAvatarUri) {
      _resolvedUrl = null;
      unawaited(_resolveThumbnail());
    }
  }

  Future<void> _resolveThumbnail() async {
    final avatarUri = widget.room?.avatar;
    _lastAvatarUri = avatarUri;
    if (avatarUri == null) return;
    final generation = ++_resolveGeneration;
    try {
      final uri = await avatarUri.getThumbnailUri(
        widget.room!.client,
        width: 96,
        height: 96,
      );
      if (mounted && generation == _resolveGeneration) {
        setState(() => _resolvedUrl = uri.toString());
      }
    } catch (e) {
      debugPrint('[Lattice] Failed to resolve space avatar thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.isSelected ? 14.0 : 22.0;
    final size = widget.isSelected ? 48.0 : 44.0;

    Widget iconContent;
    if (widget.icon != null) {
      iconContent = Center(
        child: Icon(
          widget.icon,
          size: 22,
          color: widget.isSelected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      );
    } else if (_resolvedUrl != null) {
      iconContent = CachedNetworkImage(
        imageUrl: _resolvedUrl!,
        httpHeaders: mediaAuthHeaders(widget.room!.client, _resolvedUrl!),
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: (_, __) => _LetterFallback(
          label: widget.label,
          outlined: widget.outlined,
          isSelected: widget.isSelected,
        ),
        errorWidget: (_, __, ___) => _LetterFallback(
          label: widget.label,
          outlined: widget.outlined,
          isSelected: widget.isSelected,
        ),
      );
    } else {
      iconContent = _LetterFallback(
        label: widget.label,
        outlined: widget.outlined,
        isSelected: widget.isSelected,
      );
    }

    Widget icon = GestureDetector(
      onSecondaryTapUp: widget.onSecondaryTapUp,
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.outlined
                  ? Colors.transparent
                  : _resolvedUrl != null
                      ? null
                      : widget.isSelected
                          ? widget.color
                          : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(radius),
              border: widget.outlined
                  ? Border.all(
                      color: cs.outlineVariant,
                      width: 1.5,
                    )
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                mouseCursor: SystemMouseCursors.click,
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                child: iconContent,
              ),
            ),
          ),
        ),
      ),
    );

    // Overlay unread badge
    if (widget.unreadCount != null && widget.unreadCount! > 0) {
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
                  widget.unreadCount! > 99 ? '99+' : '${widget.unreadCount}',
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

class _LetterFallback extends StatelessWidget {
  const _LetterFallback({
    required this.label,
    required this.outlined,
    required this.isSelected,
  });

  final String label;
  final bool outlined;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: outlined ? 20 : 16,
          fontWeight: FontWeight.w600,
          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AccountButton extends StatefulWidget {
  const _AccountButton({required this.cs});
  final ColorScheme cs;

  @override
  State<_AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<_AccountButton> {
  Uri? _avatarUrl;
  String? _lastUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<MatrixService>().client.userID;
    if (userId != _lastUserId) {
      _lastUserId = userId;
      unawaited(_fetchProfile());
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final client = context.read<MatrixService>().client;
      final profile = await client.fetchOwnProfile();
      if (mounted) setState(() => _avatarUrl = profile.avatarUrl);
    } catch (e) {
      debugPrint('[Lattice] Failed to fetch profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final manager = context.watch<ClientManager>();
    final matrix = context.watch<MatrixService>();
    final userId = matrix.client.userID;

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      offset: const Offset(64, 0),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.settings:
            context.goNamed(Routes.settings);
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
                  UserAvatar(
                    client: manager.services[i].client,
                    userId: manager.services[i].client.userID,
                    size: 28,
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
        child: UserAvatar(
          client: matrix.client,
          avatarUrl: _avatarUrl,
          userId: userId,
          size: 36,
        ),
      ),
    );
  }
}

enum _AccountAction { settings, switchAccount }
