import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/invite_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class MobileSpaceDrawer extends StatelessWidget {
  const MobileSpaceDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topLevel = selection.topLevelSpaces;
    final invited = selection.invitedSpaces;
    final homeSelected = selection.selectedSpaceIds.isEmpty;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Spaces',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.home_rounded, color: cs.onPrimaryContainer),
              ),
              title: const Text('Home'),
              selected: homeSelected,
              onTap: () {
                selection.clearSpaceSelection();
                Navigator.of(context).pop();
              },
            ),
            if (topLevel.isNotEmpty) const Divider(height: 8),
            for (final space in topLevel)
              _SpaceTile(
                space: space,
                selected: selection.selectedSpaceIds.contains(space.id),
                unread: selection.unreadCountForSpace(space.id),
                onTap: () {
                  selection.selectSpace(space.id);
                  Navigator.of(context).pop();
                },
              ),
            if (invited.isNotEmpty) ...[
              const Divider(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Invited',
                  style: tt.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final space in invited)
                ListTile(
                  leading: Opacity(
                    opacity: 0.7,
                    child: RoomAvatarWidget(room: space, size: 36),
                  ),
                  title: Text(space.getLocalizedDisplayname()),
                  onTap: () async {
                    final result = await InviteDialog.show(context, room: space);
                    if (result == true && context.mounted) {
                      selection.selectSpace(space.id);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                ),
            ],
            const Divider(height: 8),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: cs.primary),
              title: const Text('Create space'),
              onTap: () {
                final matrix = context.read<MatrixService>();
                Navigator.of(context).pop();
                unawaited(CreateSpaceDialog.show(context, matrixService: matrix));
              },
            ),
            ListTile(
              leading: Icon(Icons.tag, color: cs.primary),
              title: const Text('Join space'),
              onTap: () {
                final matrix = context.read<MatrixService>();
                Navigator.of(context).pop();
                unawaited(JoinSpaceDialog.show(context, matrixService: matrix));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.space,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  final Room space;
  final bool selected;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: RoomAvatarWidget(room: space, size: 36),
      title: Text(space.getLocalizedDisplayname()),
      selected: selected,
      trailing: unread > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
