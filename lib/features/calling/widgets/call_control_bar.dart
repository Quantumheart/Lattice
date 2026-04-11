import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// coverage:ignore-start

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
    this.isScreenAudioEnabled = false,
    this.onToggleScreenAudio,
    this.isPTTActive = false,
    this.isPTTKeyHeld = false,
    this.isSpeakerOn,
    this.onToggleSpeaker,
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
  final bool isScreenAudioEnabled;
  final VoidCallback? onToggleScreenAudio;
  final bool isPTTActive;
  final bool isPTTKeyHeld;
  final bool? isSpeakerOn;
  final VoidCallback? onToggleSpeaker;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _MicButton(
              isMuted: isMicMuted,
              isPTTActive: isPTTActive,
              isPTTKeyHeld: isPTTKeyHeld,
              onPressed: onToggleMic,
            ),
            _ControlButton(
              icon: Icons.videocam,
              activeIcon: Icons.videocam_off,
              isActive: isCameraOff,
              onPressed: onToggleCamera,
              tooltip: isCameraOff ? 'Turn on camera' : 'Turn off camera',
            ),
            if (onFlipCamera != null &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS))
              _ControlButton(
                icon: Icons.cameraswitch,
                activeIcon: Icons.cameraswitch,
                isActive: false,
                onPressed: onFlipCamera!,
                tooltip: 'Flip camera',
              ),
            _ControlButton(
              icon: Icons.screen_share,
              activeIcon: Icons.stop_screen_share,
              isActive: isScreenSharing,
              onPressed: onToggleScreenShare,
              tooltip: isScreenSharing ? 'Stop sharing' : 'Share screen',
            ),
            if (isScreenSharing && onToggleScreenAudio != null)
              _ControlButton(
                icon: Icons.volume_up,
                activeIcon: Icons.volume_off,
                isActive: !isScreenAudioEnabled,
                onPressed: onToggleScreenAudio!,
                tooltip: isScreenAudioEnabled
                    ? 'Stop sharing audio'
                    : 'Share system audio',
              ),
            if (onToggleSpeaker != null && isSpeakerOn != null)
              _ControlButton(
                icon: Icons.volume_up_rounded,
                activeIcon: Icons.volume_off_rounded,
                isActive: !isSpeakerOn!,
                onPressed: onToggleSpeaker!,
                tooltip: isSpeakerOn! ? 'Speaker off' : 'Speaker on',
              ),
            _HangUpButton(onPressed: onHangUp),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.isMuted,
    required this.isPTTActive,
    required this.isPTTKeyHeld,
    required this.onPressed,
  });

  final bool isMuted;
  final bool isPTTActive;
  final bool isPTTKeyHeld;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget button = _ControlButton(
      icon: Icons.mic,
      activeIcon: Icons.mic_off,
      isActive: isMuted,
      onPressed: onPressed,
      tooltip: isPTTActive
          ? (isPTTKeyHeld ? 'PTT active' : 'Hold key to talk')
          : (isMuted ? 'Unmute' : 'Mute'),
    );

    if (isPTTActive) {
      button = Badge(
        label: Text(
          'PTT',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isPTTKeyHeld ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
        backgroundColor: isPTTKeyHeld ? cs.primary : cs.surfaceContainerHighest,
        child: button,
      );
    }

    return button;
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
// coverage:ignore-end
