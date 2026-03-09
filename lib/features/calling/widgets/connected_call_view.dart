import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/pip_self_view.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class ConnectedCallView extends StatelessWidget {
  const ConnectedCallView({super.key});

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final tt = Theme.of(context).textTheme;
    final allParticipants = callService.allParticipants;

    final localParticipant = allParticipants.length >= 2
        ? allParticipants.where((p) => p.isLocal).firstOrNull
        : null;

    final gridParticipants = localParticipant != null
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
          onToggleScreenShare: callService.toggleScreenShare,
          onHangUp: callService.leaveCall,
        ),
      ],
    );
  }
}
