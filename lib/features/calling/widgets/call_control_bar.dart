import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_controller.dart';

class CallControlBar extends StatelessWidget {
  const CallControlBar({required this.controller, super.key});

  final CallController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(
              icon: Icons.mic,
              activeIcon: Icons.mic_off,
              isActive: controller.isMicMuted,
              onPressed: controller.toggleMic,
              tooltip: controller.isMicMuted ? 'Unmute' : 'Mute',
            ),
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.videocam,
              activeIcon: Icons.videocam_off,
              isActive: controller.isCameraOff,
              onPressed: controller.toggleCamera,
              tooltip: controller.isCameraOff
                  ? 'Turn on camera'
                  : 'Turn off camera',
            ),
            if (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS) ...[
              const SizedBox(width: 12),
              _ControlButton(
                icon: Icons.cameraswitch,
                activeIcon: Icons.cameraswitch,
                isActive: false,
                onPressed: controller.flipCamera,
                tooltip: 'Flip camera',
              ),
            ],
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.screen_share,
              activeIcon: Icons.stop_screen_share,
              isActive: controller.isScreenSharing,
              onPressed: controller.toggleScreenShare,
              tooltip: controller.isScreenSharing
                  ? 'Stop sharing'
                  : 'Share screen',
            ),
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.volume_up,
              activeIcon: Icons.volume_up,
              isActive: false,
              onPressed: () => _showAudioDeviceSheet(context),
              tooltip: 'Audio device',
            ),
            const SizedBox(width: 16),
            _HangUpButton(onPressed: controller.hangUp),
          ],
        ),
      ),
    );
  }

  void _showAudioDeviceSheet(BuildContext context) {
    unawaited(showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.speaker),
              title: const Text('Speaker'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.hearing),
              title: const Text('Earpiece'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Bluetooth'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),);
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return isActive
        ? IconButton.filled(
            icon: Icon(activeIcon),
            onPressed: onPressed,
            tooltip: tooltip,
          )
        : IconButton.filledTonal(
            icon: Icon(icon),
            onPressed: onPressed,
            tooltip: tooltip,
          );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: cs.error,
        foregroundColor: cs.onError,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: const Icon(Icons.call_end),
    );
  }
}
