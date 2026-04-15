import 'package:flutter/material.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/macos_permissions.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/platform_info.dart';
import 'package:kohera/features/calling/services/push_to_talk_service.dart';
import 'package:kohera/features/calling/widgets/call_control_bar.dart';
import 'package:kohera/features/calling/widgets/pip_self_view.dart';
import 'package:kohera/features/calling/widgets/screen_source_picker.dart';
import 'package:kohera/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

class ConnectedCallView extends StatelessWidget {
  const ConnectedCallView({super.key});

  Future<void> _toggleScreenShare(
    BuildContext context,
    CallService callService,
  ) async {
    if (callService.isScreenShareEnabled) {
      await callService.toggleScreenShare();
      return;
    }

    if (isNativeMacOS) {
      final hasPermission = await MacOsPermissions.checkScreenCapture() ||
          await MacOsPermissions.requestScreenCapture();
      if (!hasPermission) {
        if (context.mounted) await _showScreenCapturePermissionDialog(context);
        return;
      }
    }

    if (!context.mounted) return;
    final needsSourcePicker = isNativeMacOS || isNativeWindows;
    if (needsSourcePicker) {
      final source = await showScreenSourcePicker(context);
      if (source == null) return;
      await callService.toggleScreenShare(sourceId: source.id);
    } else {
      await callService.toggleScreenShare();
    }
  }

  Future<void> _showScreenCapturePermissionDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Screen Recording Permission Required'),
        content: const Text(
          'Kohera needs screen recording permission to share your screen. '
          'Please enable it in System Settings > Privacy & Security > '
          'Screen Recording, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final tt = Theme.of(context).textTheme;
    final allParticipants = callService.allParticipants;

    final localParticipant = allParticipants.length >= 2
        ? allParticipants.where((p) => p.isLocal).firstOrNull
        : null;

    final localIsSharing = localParticipant?.screenShareTrack != null;
    final gridParticipants = localParticipant != null && !localIsSharing
        ? allParticipants.where((p) => !p.isLocal).toList()
        : allParticipants;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              VideoGrid(participants: gridParticipants),
              if (localParticipant != null)
                PipSelfView(participant: localParticipant),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${allParticipants.length} participant${allParticipants.length == 1 ? '' : 's'}',
            style: tt.titleMedium,
          ),
        ),
        Builder(
          builder: (ctx) {
            final prefs = ctx.watch<PreferencesService>();
            final ptt = ctx.watch<PushToTalkService>();

            return CallControlBar(
              isMicMuted: !callService.isMicEnabled,
              isCameraOff: !callService.isCameraEnabled,
              isScreenSharing: callService.isScreenShareEnabled,
              isScreenAudioEnabled: callService.isScreenAudioEnabled,
              onToggleMic: callService.toggleMicrophone,
              onToggleCamera: callService.toggleCamera,
              onToggleScreenShare: () =>
                  _toggleScreenShare(context, callService),
              onToggleScreenAudio:
                  isNativeDesktop ? callService.toggleScreenAudio : null,
              onHangUp: callService.leaveCall,
              isPTTActive: prefs.pushToTalkEnabled,
              isPTTKeyHeld: ptt.isKeyHeld,
              isSpeakerOn: isNativeMobile ? callService.isSpeakerOn : null,
              onToggleSpeaker:
                  isNativeMobile ? callService.toggleSpeaker : null,
            );
          },
        ),
      ],
    );
  }
}
// coverage:ignore-end
