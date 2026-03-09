import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/connected_call_view.dart';
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
