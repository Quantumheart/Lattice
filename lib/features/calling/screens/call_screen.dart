import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/features/calling/services/call_controller.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/services/call_service.dart';
import 'package:lattice/features/calling/widgets/call_control_bar.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/pip_self_view.dart';
import 'package:lattice/features/calling/widgets/video_grid.dart';
import 'package:provider/provider.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({required this.roomId, required this.displayName, super.key});

  final String roomId;
  final String displayName;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallService _callService;
  Timer? _popTimer;

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _callService.activeCall;
    if (controller == null || controller.state == CallState.ended) {
      _popTimer ??= Timer(const Duration(seconds: 2), () {
        if (mounted) unawaited(CallNavigator.endCall(context));
      });
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _callService = context.read<CallService>();
    _callService.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _callService.removeListener(_onControllerChanged);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final controller = callService.activeCall;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: controller == null ||
          (controller.state != CallState.connected &&
              controller.state != CallState.reconnecting),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
        ),
        body: controller == null
            ? const CallEndedView()
            : switch (controller.state) {
                CallState.joining => CallJoiningView(displayName: widget.displayName),
                CallState.connected => _buildConnected(tt, controller),
                CallState.reconnecting => const CallReconnectingView(),
                CallState.ended => CallEndedView(error: controller.error),
              },
      ),
    );
  }

  // ── Connected view ──────────────────────────────────────────

  Widget _buildConnected(TextTheme tt, CallController controller) {
    final remoteParticipants = controller.participants
        .where((p) => !p.isLocal)
        .toList();
    final localParticipant = controller.participants
        .where((p) => p.isLocal)
        .firstOrNull;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: VideoGrid(participants: remoteParticipants),
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
        ),
        if (localParticipant != null)
          PipSelfView(participant: localParticipant),
      ],
    );
  }
}
