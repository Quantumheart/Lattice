import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/services/call_navigator.dart';
import 'package:lattice/features/calling/widgets/call_state_views.dart';
import 'package:lattice/features/calling/widgets/connected_call_view.dart';
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

  void _onCallChanged() {
    if (!mounted) return;
    final state = _callService.callState;
    if (state == LatticeCallState.idle || state == LatticeCallState.failed) {
      _popTimer ??= Timer(const Duration(seconds: 2), () {
        if (mounted) unawaited(CallNavigator.endCall(context));
      });
    } else if (_popTimer != null) {
      _popTimer!.cancel();
      _popTimer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _callService = context.read<CallService>();
    _callService.addListener(_onCallChanged);
  }

  @override
  void dispose() {
    _popTimer?.cancel();
    _callService.removeListener(_onCallChanged);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final state = callService.callState;

    return PopScope(
      canPop: state != LatticeCallState.connected &&
          state != LatticeCallState.reconnecting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.displayName),
        ),
        body: switch (state) {
          LatticeCallState.ringingOutgoing => CallRingingOutgoingView(
              displayName: widget.displayName,
              onCancel: callService.cancelOutgoingCall,
            ),
          LatticeCallState.ringingIncoming => CallJoiningView(displayName: widget.displayName),
          LatticeCallState.joining => CallJoiningView(displayName: widget.displayName),
          LatticeCallState.connected => const ConnectedCallView(),
          LatticeCallState.reconnecting => const CallReconnectingView(),
          LatticeCallState.disconnecting ||
          LatticeCallState.idle ||
          LatticeCallState.failed => const CallEndedView(),
        },
      ),
    );
  }

}
