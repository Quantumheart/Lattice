import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/features/calling/services/call_navigator.dart';
import 'package:kohera/features/calling/widgets/call_state_views.dart';
import 'package:kohera/features/calling/widgets/connected_call_view.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

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
    if (state == KoheraCallState.idle || state == KoheraCallState.failed) {
      _popTimer ??= Timer(const Duration(seconds: 2), () {
        _popTimer = null;
        if (mounted) unawaited(CallNavigator.endCall(context));
      });
    } else {
      _popTimer?.cancel();
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo(
            Routes.room,
            pathParameters: {'roomId': widget.roomId},
          ),
        ),
        title: Text(widget.displayName),
      ),
      body: switch (state) {
        KoheraCallState.ringingOutgoing => CallRingingOutgoingView(
            displayName: widget.displayName,
            onCancel: callService.cancelOutgoingCall,
          ),
        KoheraCallState.ringingIncoming => CallJoiningView(displayName: widget.displayName),
        KoheraCallState.joining => CallJoiningView(displayName: widget.displayName),
        KoheraCallState.connected => const ConnectedCallView(),
        KoheraCallState.reconnecting => const CallReconnectingView(),
        KoheraCallState.disconnecting ||
        KoheraCallState.idle ||
        KoheraCallState.failed => const CallEndedView(),
      },
    );
  }

}
// coverage:ignore-end
