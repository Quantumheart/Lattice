import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/pip_self_view.dart';
import 'package:lattice/features/calling/widgets/screen_source_picker.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
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

    final isDesktop =
        !kIsWeb && !Platform.isAndroid && !Platform.isIOS;
    if (isDesktop) {
      final source = await showScreenSourcePicker(context);
      if (source == null) return;
      await callService.toggleScreenShare(sourceId: source.id);
    } else {
      await callService.toggleScreenShare();
    }
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
        CallControlBar(
          isMicMuted: !callService.isMicEnabled,
          isCameraOff: !callService.isCameraEnabled,
          isScreenSharing: callService.isScreenShareEnabled,
          onToggleMic: callService.toggleMicrophone,
          onToggleCamera: callService.toggleCamera,
          onToggleScreenShare: () => _toggleScreenShare(context, callService),
          onHangUp: callService.leaveCall,
        ),
      ],
    );
  }
}
// coverage:ignore-end
