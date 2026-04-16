import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/home/widgets/inbox_screen.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/features/rooms/widgets/room_list.dart';
import 'package:kohera/features/settings/screens/settings_screen.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

class NarrowLayout extends StatefulWidget {
  const NarrowLayout({
    required this.routerChild,
    required this.routeName,
    required this.roomId,
    super.key,
  });

  final Widget routerChild;
  final String? routeName;
  final String? roomId;

  @override
  State<NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends State<NarrowLayout> {
  bool _initialTabApplied = false;

  MobileTab _tabForRoute(String? name) {
    if (name == Routes.inbox) return MobileTab.inbox;
    if (name == Routes.settings) return MobileTab.you;
    return MobileTab.chats;
  }

  String _routeForTab(MobileTab tab) {
    switch (tab) {
      case MobileTab.inbox:
        return Routes.inbox;
      case MobileTab.chats:
        return Routes.home;
      case MobileTab.you:
        return Routes.settings;
    }
  }

  bool _isHideChromeRoute(String? name) {
    if (name == null) return false;
    if ((name == Routes.room || name == Routes.call || name == Routes.roomDetails) &&
        widget.roomId != null) {
      return true;
    }
    return name == Routes.settingsAppearance ||
        name == Routes.settingsNotifications ||
        name == Routes.settingsDevices ||
        name == Routes.settingsVoiceVideo ||
        name == Routes.spaceDetails;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.routeName;

    if (_isHideChromeRoute(name)) {
      return widget.routerChild;
    }

    if (!_initialTabApplied && name == Routes.home) {
      _initialTabApplied = true;
      final remembered = context.read<PreferencesService>().lastMobileTab;
      if (remembered != MobileTab.chats) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.goNamed(_routeForTab(remembered));
        });
      }
    }

    final currentTab = _tabForRoute(name);
    final unread = context.select<InboxController, int>((c) => c.unreadCount);

    return Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: currentTab.index,
            children: const [
              InboxScreen(),
              RoomList(),
              SettingsScreen(),
            ],
          ),
        ),
        NavigationBar(
          selectedIndex: currentTab.index,
          onDestinationSelected: (i) async {
            final tab = MobileTab.values[i];
            final prefs = context.read<PreferencesService>();
            await prefs.setLastMobileTab(tab);
            if (context.mounted) context.goNamed(_routeForTab(tab));
          },
          destinations: [
            NavigationDestination(
              icon: unread > 0
                  ? Badge(
                      label: Text(unread > 99 ? '99+' : '$unread'),
                      child: const Icon(Icons.inbox_outlined),
                    )
                  : const Icon(Icons.inbox_outlined),
              selectedIcon: const Icon(Icons.inbox),
              label: MobileTab.inbox.label,
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: MobileTab.chats.label,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: MobileTab.you.label,
            ),
          ],
        ),
      ],
    );
  }
}
// coverage:ignore-end
