import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class CallPane extends StatelessWidget {
  const CallPane({super.key});

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final state = callService.callState;

    return switch (state) {
      LatticeCallState.ringingOutgoing => CallRingingOutgoingView(
          displayName: 'Call',
          onCancel: callService.cancelOutgoingCall,
        ),
      LatticeCallState.ringingIncoming ||
      LatticeCallState.joining => const CallJoiningView(displayName: 'Call'),
      LatticeCallState.connected => _buildConnected(context, callService),
      LatticeCallState.reconnecting => const CallReconnectingView(),
      LatticeCallState.disconnecting ||
      LatticeCallState.idle => const Center(child: Text('No active call')),
      LatticeCallState.failed => CallEndedView(
          onReturn: () => CallNavigator.endCall(context),
        ),
    };
  }

  Widget _buildConnected(BuildContext context, CallService callService) {
    final tt = Theme.of(context).textTheme;
    final speakers = callService.activeSpeakers;
    final tiles = callService.participants
        .map((p) => CallParticipant.fromRemote(p, activeSpeakers: speakers))
        .toList();
    return Column(
      children: [
        Expanded(
          child: VideoGrid(participants: tiles),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${tiles.length} participant${tiles.length == 1 ? '' : 's'}',
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
