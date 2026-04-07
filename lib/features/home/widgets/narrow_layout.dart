import 'package:flutter/material.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/features/spaces/widgets/space_rail.dart';

// coverage:ignore-start

class NarrowLayout extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final name = routeName;

    final hideRail =
        ((name == Routes.room || name == Routes.call || name == Routes.roomDetails) && roomId != null) ||
        name == Routes.settings ||
        name == Routes.settingsAppearance ||
        name == Routes.settingsNotifications ||
        name == Routes.settingsDevices ||
        name == Routes.settingsVoiceVideo ||
        name == Routes.spaceDetails;

    if (hideRail) {
      return routerChild;
    }

    return Scaffold(
      body: Row(
        children: [
          const SpaceRail(),
          Expanded(child: routerChild),
        ],
      ),
    );
  }
}
// coverage:ignore-end
