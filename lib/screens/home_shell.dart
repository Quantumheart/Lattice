import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/space_node.dart';
import '../services/matrix_service.dart';
import '../services/preferences_service.dart';
import '../widgets/invite_dialog.dart';
import '../widgets/space_rail.dart';
import '../widgets/room_list.dart';
import '../widgets/room_details_panel.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// The root layout shell. On wide screens it shows the three-column
/// Lattice layout (rail + room list + chat). On narrow screens it uses
/// a bottom navigation bar with stack navigation.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _mobileTab = 0; // 0: chats, 1: spaces, 2: settings
  double? _dragPanelWidth; // local state during divider drag
  bool _showRoomDetails = false;
  String? _detailsPanelRoomId;

  static const double _wideBreakpoint = 720;
  static const double _extraWideBreakpoint = 1100;
  static const double _collapseThreshold = PreferencesService.collapseThreshold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final matrix = context.read<MatrixService>();
    // Close details panel when the selected room changes.
    if (_detailsPanelRoomId != null &&
        _detailsPanelRoomId != matrix.selectedRoomId) {
      setState(() => _showRoomDetails = false);
    }
    _detailsPanelRoomId = matrix.selectedRoomId;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    final matrix = context.watch<MatrixService>();

    final child = isWide ? _buildWideLayout(width, matrix) : _buildNarrowLayout(matrix);

    return CallbackShortcuts(
      bindings: _buildKeyBindings(matrix),
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(MatrixService matrix) {
    final spaces = matrix.spaces;
    final bindings = <ShortcutActivator, VoidCallback>{};

    // Ctrl+0 → clear space selection
    bindings[const SingleActivator(LogicalKeyboardKey.digit0,
        control: true)] = () => matrix.clearSpaceSelection();

    // Ctrl+1..9 → select Nth space
    final digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < digitKeys.length && i < spaces.length; i++) {
      final spaceId = spaces[i].id;
      bindings[SingleActivator(digitKeys[i], control: true)] =
          () => matrix.selectSpace(spaceId);
      // Ctrl+Shift+1..9 → toggle Nth space in multi-select
      bindings[SingleActivator(digitKeys[i], control: true, shift: true)] =
          () => matrix.toggleSpaceSelection(spaceId);
    }

    return bindings;
  }

  // ── Wide: rail + room list + chat ────────────────────────────
  Widget _buildWideLayout(double width, MatrixService matrix) {
    final showChat = width >= _extraWideBreakpoint;
    final prefs = context.watch<PreferencesService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // Space icon rail
          const SpaceRail(),

          // Room list (resizable, collapsible on desktop)
          if (showChat && _dragPanelWidth == null && prefs.panelWidth < _collapseThreshold) ...[
            // Collapsed: just show an expand button
            SizedBox(
              width: 40,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Expand room list',
                  onPressed: () {
                    setState(() => _dragPanelWidth = null);
                    prefs.setPanelWidth(PreferencesService.defaultPanelWidth);
                  },
                ),
              ),
            ),
            VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          ] else ...[
            SizedBox(
              width: showChat
                  ? (_dragPanelWidth ?? prefs.panelWidth).clamp(
                      _collapseThreshold,
                      PreferencesService.maxPanelWidth,
                    )
                  : 360,
              child: const RoomList(),
            ),

            // Draggable divider (only when chat pane is visible)
            if (showChat)
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    _dragPanelWidth = prefs.panelWidth;
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragPanelWidth = (_dragPanelWidth! + details.delta.dx)
                          .clamp(0.0, PreferencesService.maxPanelWidth);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final w = _dragPanelWidth!;
                    setState(() => _dragPanelWidth = null);
                    prefs.setPanelWidth(w < _collapseThreshold ? 0 : w);
                  },
                  child: Container(
                    width: 5,
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              )
            else
              VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          ],

          // Chat pane (or placeholder) + optional details panel
          Expanded(
            child: _buildChatAndDetails(matrix, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildChatAndDetails(MatrixService matrix, ColorScheme cs) {
    if (matrix.selectedRoomId == null) return _buildEmptyChat();

    return Row(
      children: [
        Expanded(
          child: ChatScreen(
            roomId: matrix.selectedRoomId!,
            key: ValueKey(matrix.selectedRoomId),
            onShowDetails: () => setState(() => _showRoomDetails = !_showRoomDetails),
          ),
        ),
        if (_showRoomDetails) ...[
          VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          SizedBox(
            width: 320,
            child: RoomDetailsPanel(
              roomId: matrix.selectedRoomId!,
              key: ValueKey('details-${matrix.selectedRoomId}'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyChat() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Select a conversation',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow: bottom nav ───────────────────────────────────────
  Widget _buildNarrowLayout(MatrixService matrix) {

    // If a room is selected on mobile, push the chat screen.
    if (matrix.selectedRoomId != null && _mobileTab == 0) {
      return ChatScreen(
        roomId: matrix.selectedRoomId!,
        key: ValueKey(matrix.selectedRoomId),
        onBack: () => matrix.selectRoom(null),
      );
    }

    Widget body;
    switch (_mobileTab) {
      case 0:
        body = const RoomList();
        break;
      case 1:
        body = _SpaceListMobile(
          onSpaceSelected: () => setState(() => _mobileTab = 0),
        );
        break;
      case 2:
        body = const SettingsScreen();
        break;
      default:
        body = const RoomList();
    }

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: body,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileTab,
        onDestinationSelected: (i) => setState(() => _mobileTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspaces_outlined),
            selectedIcon: Icon(Icons.workspaces_rounded),
            label: 'Spaces',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Mobile space list with search, unread badges, subspace nesting.
class _SpaceListMobile extends StatefulWidget {
  const _SpaceListMobile({required this.onSpaceSelected});

  final VoidCallback onSpaceSelected;

  @override
  State<_SpaceListMobile> createState() => _SpaceListMobileState();
}

class _SpaceListMobileState extends State<_SpaceListMobile> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    final matrix = context.read<MatrixService>();
    final prefs = context.read<PreferencesService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) matrix.updateSpaceOrder(prefs.spaceOrder);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tree = matrix.spaceTree;

    // Filter by search query
    final isSearching = _query.isNotEmpty;
    List<SpaceNode> filteredTree = tree;
    if (isSearching) {
      final q = _query.toLowerCase();
      filteredTree = _filterTree(tree, q);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Spaces')),
      body: Column(
        children: [
          // Search field
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search spaces\u2026',
                prefixIcon:
                    Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
            ),
          ),

          // Invited spaces
          Builder(
            builder: (context) {
              var invited = matrix.invitedSpaces;
              if (isSearching) {
                final q = _query.toLowerCase();
                invited = invited
                    .where((r) => r.getLocalizedDisplayname()
                        .toLowerCase()
                        .contains(q))
                    .toList();
              }
              if (invited.isEmpty) return const SizedBox.shrink();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final space in invited)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.tertiaryContainer,
                          child: Text(
                            space.getLocalizedDisplayname().isNotEmpty
                                ? space.getLocalizedDisplayname()[0]
                                    .toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: cs.onTertiaryContainer),
                          ),
                        ),
                        title: Text(space.getLocalizedDisplayname()),
                        subtitle: Builder(builder: (_) {
                          final inviter = matrix.inviterDisplayName(space);
                          return Text(
                            inviter != null
                                ? 'Invited by $inviter'
                                : 'Pending invite',
                            style: tt.bodyMedium,
                          );
                        }),
                        tileColor: cs.tertiaryContainer
                            .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        mouseCursor: SystemMouseCursors.click,
                        onTap: () async {
                          final result = await InviteDialog.show(
                            context,
                            room: space,
                          );
                          if (result == true && mounted) {
                            matrix.selectSpace(space.id);
                            widget.onSpaceSelected();
                          }
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: cs.outlineVariant),
                  ),
                ],
              );
            },
          ),

          // Space list
          Expanded(
            child: filteredTree.isEmpty
                ? Center(
                    child: Text(
                      isSearching
                          ? 'No spaces match "$_query"'
                          : 'No spaces yet',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : isSearching
                    // Plain list when searching (reordering a filtered
                    // subset doesn't make sense).
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredTree.length,
                        itemBuilder: (context, i) {
                          return _buildTopLevelItem(
                            context, matrix, filteredTree[i],
                            key: ValueKey(filteredTree[i].room.id),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredTree.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex--;
                          final ids = filteredTree
                              .map((n) => n.room.id)
                              .toList();
                          final id = ids.removeAt(oldIndex);
                          ids.insert(newIndex, id);
                          context.read<PreferencesService>().setSpaceOrder(ids);
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
                          return ReorderableDragStartListener(
                            key: ValueKey(filteredTree[i].room.id),
                            index: i,
                            child: _buildTopLevelItem(
                              context, matrix, filteredTree[i],
                              key: ValueKey('inner-${filteredTree[i].room.id}'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Builds a single top-level space item (with its subspaces) for
  /// both the reorderable and plain list views.
  Widget _buildTopLevelItem(
    BuildContext context,
    MatrixService matrix,
    SpaceNode node, {
    required Key key,
  }) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: _buildSpaceItems(context, matrix, node, 0),
    );
  }

  List<Widget> _buildSpaceItems(
    BuildContext context,
    MatrixService matrix,
    SpaceNode node,
    int depth,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selected = matrix.selectedSpaceIds.contains(node.room.id);
    final unread = matrix.unreadCountForSpace(node.room.id);
    final widgets = <Widget>[];

    widgets.add(
      Padding(
        padding: EdgeInsets.only(left: depth * 16.0),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Text(
              node.room.getLocalizedDisplayname().isNotEmpty
                  ? node.room.getLocalizedDisplayname()[0].toUpperCase()
                  : '?',
              style: TextStyle(color: cs.onPrimaryContainer),
            ),
          ),
          title: Text(node.room.getLocalizedDisplayname()),
          subtitle: Text(
            '${node.directChildRoomIds.length} rooms',
            style: tt.bodyMedium,
          ),
          trailing: unread > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.onError,
                    ),
                  ),
                )
              : null,
          selected: selected,
          selectedTileColor:
              cs.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          mouseCursor: SystemMouseCursors.click,
          onTap: () {
            matrix.selectSpace(node.room.id);
            widget.onSpaceSelected();
          },
          onLongPress: () {
            matrix.toggleSpaceSelection(node.room.id);
            widget.onSpaceSelected();
          },
        ),
      ),
    );

    for (final sub in node.subspaces) {
      widgets.addAll(
          _buildSpaceItems(context, matrix, sub, depth + 1));
    }

    return widgets;
  }

  /// Filter tree to nodes matching the query (or having matching children).
  List<SpaceNode> _filterTree(List<SpaceNode> nodes, String q) {
    final result = <SpaceNode>[];
    for (final node in nodes) {
      final nameMatches =
          node.room.getLocalizedDisplayname().toLowerCase().contains(q);
      final filteredSubs = _filterTree(node.subspaces, q);
      if (nameMatches || filteredSubs.isNotEmpty) {
        result.add(SpaceNode(
          room: node.room,
          subspaces: nameMatches ? node.subspaces : filteredSubs,
          directChildRoomIds: node.directChildRoomIds,
        ));
      }
    }
    return result;
  }
}
