import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_controller.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class CallPane extends StatelessWidget {
  const CallPane({super.key});

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final controller = callService.activeCall;
    final displayName = callService.activeDisplayName ?? 'Call';

    if (controller == null) {
      return const Center(child: Text('No active call'));
    }

    return switch (controller.state) {
      CallState.joining => CallJoiningView(displayName: displayName),
      CallState.connected => _buildConnected(context, controller),
      CallState.reconnecting => const CallReconnectingView(),
      CallState.ended => CallEndedView(
          error: controller.error,
          onReturn: () => CallNavigator.endCall(context),
        ),
    };
  }

  Widget _buildConnected(BuildContext context, CallController controller) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: VideoGrid(participants: controller.participants),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            formatCallElapsed(controller.elapsed),
            style: tt.titleMedium,
          ),
        ),
        CallControlBar.fromController(controller),
      ],
    );
  }
}
