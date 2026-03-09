import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/matrix_service.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/connected_call_view.dart';
import 'package:provider/provider.dart';

class CallPane extends StatelessWidget {
  const CallPane({super.key});

  String _resolveRoomName(BuildContext context, CallService callService) {
    final roomId = callService.activeCallRoomId;
    if (roomId == null) return 'Call';
    final room = context.read<MatrixService>().client.getRoomById(roomId);
    return room?.getLocalizedDisplayname() ?? 'Call';
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final state = callService.callState;

    return switch (state) {
      LatticeCallState.ringingOutgoing => CallRingingOutgoingView(
          displayName: _resolveRoomName(context, callService),
          onCancel: callService.cancelOutgoingCall,
        ),
      LatticeCallState.ringingIncoming ||
      LatticeCallState.joining => CallJoiningView(
          displayName: _resolveRoomName(context, callService),
        ),
      LatticeCallState.connected => const ConnectedCallView(),
      LatticeCallState.reconnecting => const CallReconnectingView(),
      LatticeCallState.disconnecting ||
      LatticeCallState.idle => const Center(child: Text('No active call')),
      LatticeCallState.failed => CallEndedView(
          onReturn: () => CallNavigator.endCall(context),
        ),
    };
  }
}
