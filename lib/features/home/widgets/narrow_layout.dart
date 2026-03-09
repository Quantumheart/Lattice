import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/calling/screens/call_screen.dart';
import 'package:lattice/features/chat/screens/chat_screen.dart';
import 'package:lattice/features/rooms/widgets/room_list.dart';
import 'package:lattice/features/settings/screens/settings_screen.dart';
import 'package:lattice/features/spaces/widgets/space_rail.dart';
import 'package:provider/provider.dart';

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
    final Widget content;
    final name = routeName;

    if (name == Routes.call && roomId != null) {
      final matrix = context.read<MatrixService>();
      final room = matrix.client.getRoomById(roomId!);
      content = CallScreen(
        roomId: roomId!,
        displayName: room?.getLocalizedDisplayname() ?? 'Call',
      );
    } else if (name == Routes.room && roomId != null) {
      content = ChatScreen(
        roomId: roomId!,
        key: ValueKey(roomId),
        onBack: () => context.goNamed(Routes.home),
      );
    } else if (name == Routes.settings) {
      content = const SettingsScreen();
    } else if (name == Routes.home || name == null) {
      content = const RoomList();
    } else {
      content = routerChild;
    }

    final hideRail = (name == Routes.room || name == Routes.call) && roomId != null;
    if (hideRail) {
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
