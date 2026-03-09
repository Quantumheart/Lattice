import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class CallControlBar extends StatelessWidget {
  const CallControlBar({
    required this.isMicMuted,
    required this.isCameraOff,
    required this.isScreenSharing,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onHangUp,
    this.onFlipCamera,
    super.key,
  });

  final bool isMicMuted;
  final bool isCameraOff;
  final bool isScreenSharing;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onHangUp;
  final VoidCallback? onFlipCamera;

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
              isActive: isMicMuted,
              onPressed: onToggleMic,
              tooltip: isMicMuted ? 'Unmute' : 'Mute',
            ),
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.videocam,
              activeIcon: Icons.videocam_off,
              isActive: isCameraOff,
              onPressed: onToggleCamera,
              tooltip: isCameraOff ? 'Turn on camera' : 'Turn off camera',
            ),
            if (onFlipCamera != null &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS)) ...[
              const SizedBox(width: 12),
              _ControlButton(
                icon: Icons.cameraswitch,
                activeIcon: Icons.cameraswitch,
                isActive: false,
                onPressed: onFlipCamera!,
                tooltip: 'Flip camera',
              ),
            ],
            const SizedBox(width: 12),
            _ControlButton(
              icon: Icons.screen_share,
              activeIcon: Icons.stop_screen_share,
              isActive: isScreenSharing,
              onPressed: onToggleScreenShare,
              tooltip: isScreenSharing ? 'Stop sharing' : 'Share screen',
            ),
            const SizedBox(width: 16),
            _HangUpButton(onPressed: onHangUp),
          ],
        ),
      ),
    );
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
