import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/chat/screens/chat_screen.dart';
import 'package:lattice/features/rooms/widgets/room_details_panel.dart';
import 'package:lattice/features/rooms/widgets/room_list.dart';
import 'package:lattice/features/settings/screens/settings_screen.dart';
import 'package:lattice/features/spaces/widgets/space_rail.dart';
import 'package:lattice/features/spaces/widgets/space_reparent_controller.dart';
import 'package:provider/provider.dart';

/// The root layout shell. On wide screens it shows the three-column
/// Lattice layout (rail + room list + chat). On narrow screens it shows
/// the space rail + room list, with full-screen push for chat.
///
/// Receives the [routerChild] and [routerState] from the [ShellRoute]
/// so it can display the matched route's content in the appropriate pane.
class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.routerChild, required this.routerState, super.key,
  });

  final Widget routerChild;
  final GoRouterState routerState;

  static const double wideBreakpoint = 720;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  double? _dragPanelWidth; // local state during divider drag
  bool _showRoomDetails = false;
  bool _syncScheduled = false;
  bool _wasWide = false;

  static const double _wideBreakpoint = HomeShell.wideBreakpoint;
  static const double _extraWideBreakpoint = 1100;
  static const double _collapseThreshold = PreferencesService.collapseThreshold;

  // ── Route → MatrixService sync ──────────────────────────────

  String? get _routeRoomId => widget.routerState.pathParameters['roomId'];
  String? get _routeName => widget.routerState.topRoute?.name;

  void _syncRoomSelection() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      final matrix = context.read<MatrixService>();
      final roomId = _routeRoomId;
      if (matrix.selectedRoomId != roomId) {
        matrix.selectRoom(roomId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeShell old) {
    super.didUpdateWidget(old);
    final oldRoomId = old.routerState.pathParameters['roomId'];
    final newRoomId = _routeRoomId;

    if (oldRoomId != newRoomId) {
      // Sync route → MatrixService so NotificationService and other
      // non-widget consumers stay up to date.
      _syncRoomSelection();

      // Close details panel when the selected room changes.
      _showRoomDetails = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncRoomSelection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;
    if (_wasWide && !isWide) {
      _showRoomDetails = false;
    }
    _wasWide = isWide;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    // Only rebuild when spaces change (for keyboard bindings).
    final matrix = context.read<MatrixService>();
    context.select<MatrixService, int>((m) => Object.hashAll(m.spaces.map((s) => s.id)));

    final child = isWide
        ? _buildWideLayout(width, matrix)
        : _buildNarrowLayout(matrix);

    return ChangeNotifierProvider<SpaceReparentController>(
      create: (_) => SpaceReparentController(),
      child: CallbackShortcuts(
        bindings: _buildKeyBindings(matrix),
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(MatrixService matrix) {
    final spaces = matrix.topLevelSpaces;
    final bindings = <ShortcutActivator, VoidCallback>{};

    // Ctrl+0 → clear space selection
    bindings[const SingleActivator(LogicalKeyboardKey.digit0,
        control: true,)] = () => matrix.clearSpaceSelection();

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
                    final current = _dragPanelWidth ?? prefs.panelWidth;
                    setState(() {
                      _dragPanelWidth = (current + details.delta.dx)
                          .clamp(_collapseThreshold * 0.5, PreferencesService.maxPanelWidth);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final w = _dragPanelWidth ?? prefs.panelWidth;
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

          // Content pane (chat, settings, or placeholder) + optional details
          Expanded(
            child: _buildContentPane(cs),
          ),
        ],
      ),
    );
  }

  /// Builds the main content pane for the wide layout.
  ///
  /// For room routes, shows ChatScreen with an optional details side panel.
  /// For other routes (settings, etc.), shows the router child directly.
  Widget _buildContentPane(ColorScheme cs) {
    final roomId = _routeRoomId;
    final name = _routeName;

    // Non-room routes: show the router child (settings, spaces, etc.)
    if (name == Routes.settings ||
        name == Routes.settingsNotifications ||
        name == Routes.settingsDevices ||
        name == Routes.spaces ||
        name == Routes.spaceDetails ||
        name == Routes.inbox) {
      return widget.routerChild;
    }

    // No room selected: show placeholder.
    if (roomId == null) return _buildEmptyChat();

    // Room selected: show chat + optional details panel.
    return Row(
      children: [
        Expanded(
          child: ChatScreen(
            roomId: roomId,
            key: ValueKey(roomId),
            onShowDetails: () => setState(() => _showRoomDetails = !_showRoomDetails),
          ),
        ),
        if (_showRoomDetails) ...[
          VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
          SizedBox(
            width: 320,
            child: RoomDetailsPanel(
              roomId: roomId,
              key: ValueKey('details-$roomId'),
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
              size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.3),),
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

  // ── Narrow: space rail + content ─────────────────────────────
  Widget _buildNarrowLayout(MatrixService matrix) {

    // Determine the content pane next to the rail.
    final Widget content;
    final name = _routeName;
    if (name == Routes.room && _routeRoomId != null) {
      content = ChatScreen(
        roomId: _routeRoomId!,
        key: ValueKey(_routeRoomId),
        onBack: () => context.goNamed(Routes.home),
      );
    } else if (name == Routes.settings) {
      content = const SettingsScreen();
    } else if (name == Routes.home || name == null) {
      content = const RoomList();
    } else {
      // roomDetails, settingsNotifications, settingsDevices,
      // spaceDetails, inbox, etc.
      content = widget.routerChild;
    }

    // Hide the space rail when viewing a chat room on narrow layout.
    if (name == Routes.room && _routeRoomId != null) {
      return Scaffold(body: content);
    }

    return Scaffold(
      body: Row(
        children: [
          const SpaceRail(),
          Expanded(child: content),
        ],
      ),
    );
  }
}
