import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';
import '../widgets/space_rail.dart';
import '../widgets/room_list.dart';
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

  static const double _wideBreakpoint = 720;
  static const double _extraWideBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    if (isWide) {
      return _buildWideLayout(width);
    }
    return _buildNarrowLayout();
  }

  // ── Wide: rail + room list + chat ────────────────────────────
  Widget _buildWideLayout(double width) {
    final showChat = width >= _extraWideBreakpoint;
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // Space icon rail
          const SpaceRail(),

          // Room list
          SizedBox(
            width: showChat ? 320 : 360,
            child: const RoomList(),
          ),

          // Divider
          VerticalDivider(width: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

          // Chat pane (or placeholder)
          Expanded(
            child: matrix.selectedRoomId != null
                ? ChatScreen(
                    roomId: matrix.selectedRoomId!,
                    key: ValueKey(matrix.selectedRoomId),
                  )
                : _buildEmptyChat(),
          ),
        ],
      ),
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
  Widget _buildNarrowLayout() {
    final matrix = context.watch<MatrixService>();

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
        body = const _SpaceListMobile();
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

/// Simple space list for mobile (the rail is desktop-only).
class _SpaceListMobile extends StatelessWidget {
  const _SpaceListMobile();

  @override
  Widget build(BuildContext context) {
    final matrix = context.watch<MatrixService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final spaces = matrix.spaces;

    return Scaffold(
      appBar: AppBar(title: const Text('Spaces')),
      body: spaces.isEmpty
          ? Center(
              child: Text(
                'No spaces yet',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: spaces.length,
              itemBuilder: (context, i) {
                final space = spaces[i];
                final selected = matrix.selectedSpaceId == space.id;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      space.getLocalizedDisplayname().isNotEmpty
                          ? space.getLocalizedDisplayname()[0].toUpperCase()
                          : '?',
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                  ),
                  title: Text(space.getLocalizedDisplayname()),
                  subtitle: Text(
                    '${space.spaceChildren.length} rooms',
                    style: tt.bodyMedium,
                  ),
                  selected: selected,
                  selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () {
                    matrix.selectSpace(selected ? null : space.id);
                  },
                );
              },
            ),
    );
  }
}
