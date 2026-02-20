import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../extensions/device_extension.dart';

/// A list tile displaying a single Matrix device with its verification status.
class DeviceListItem extends StatelessWidget {
  const DeviceListItem({
    super.key,
    required this.device,
    required this.isCurrentDevice,
    this.deviceKeys,
    this.onRename,
    this.onVerify,
    this.onToggleBlock,
    this.onRemove,
  });

  final Device device;
  final bool isCurrentDevice;
  final DeviceKeys? deviceKeys;
  final VoidCallback? onRename;
  final VoidCallback? onVerify;
  final VoidCallback? onToggleBlock;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(device.deviceIcon, color: cs.onSurfaceVariant),
      title: Text(
        device.displayNameOrId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(device.lastActiveString),
          const SizedBox(height: 2),
          _VerificationBadge(
            isVerified: deviceKeys?.verified ?? false,
            isBlocked: deviceKeys?.blocked ?? false,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: isCurrentDevice
          ? null
          : PopupMenuButton<_DeviceAction>(
              onSelected: (action) {
                switch (action) {
                  case _DeviceAction.rename:
                    onRename?.call();
                  case _DeviceAction.verify:
                    onVerify?.call();
                  case _DeviceAction.block:
                    onToggleBlock?.call();
                  case _DeviceAction.remove:
                    onRemove?.call();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _DeviceAction.rename,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
                    dense: true,
                  ),
                ),
                if (deviceKeys != null && !(deviceKeys!.blocked))
                  const PopupMenuItem(
                    value: _DeviceAction.verify,
                    child: ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text('Verify'),
                      dense: true,
                    ),
                  ),
                if (deviceKeys != null)
                  PopupMenuItem(
                    value: _DeviceAction.block,
                    child: ListTile(
                      leading: Icon(
                        deviceKeys!.blocked
                            ? Icons.shield_outlined
                            : Icons.block_outlined,
                      ),
                      title: Text(deviceKeys!.blocked ? 'Unblock' : 'Block'),
                      dense: true,
                    ),
                  ),
                PopupMenuItem(
                  value: _DeviceAction.remove,
                  child: ListTile(
                    leading: Icon(Icons.delete_outlined, color: cs.error),
                    title: Text('Remove', style: TextStyle(color: cs.error)),
                    dense: true,
                  ),
                ),
              ],
            ),
      onTap: isCurrentDevice ? onRename : null,
    );
  }
}

enum _DeviceAction { rename, verify, block, remove }

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({
    required this.isVerified,
    required this.isBlocked,
  });

  final bool isVerified;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final (IconData icon, String label, Color color) = isBlocked
        ? (Icons.block, 'Blocked', cs.error)
        : isVerified
            ? (Icons.verified, 'Verified', cs.primary)
            : (Icons.shield_outlined, 'Unverified', cs.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: tt.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
