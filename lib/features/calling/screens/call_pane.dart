import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/calling/services/call_navigator.dart';
import 'package:kohera/features/calling/widgets/call_state_views.dart';
import 'package:kohera/features/calling/widgets/connected_call_view.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start

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
    final roomId = callService.activeCallRoomId;

    final body = switch (state) {
      KoheraCallState.ringingOutgoing => CallRingingOutgoingView(
          displayName: _resolveRoomName(context, callService),
          onCancel: callService.cancelOutgoingCall,
        ),
      KoheraCallState.ringingIncoming ||
      KoheraCallState.joining => CallJoiningView(
          displayName: _resolveRoomName(context, callService),
        ),
      KoheraCallState.connected => const ConnectedCallView(),
      KoheraCallState.reconnecting => const CallReconnectingView(),
      KoheraCallState.disconnecting ||
      KoheraCallState.idle => const Center(child: Text('No active call')),
      KoheraCallState.failed => CallEndedView(
          onReturn: () => CallNavigator.endCall(context),
        ),
    };

    return Column(
      children: [
        if (roomId != null &&
            state != KoheraCallState.idle &&
            state != KoheraCallState.failed)
          AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.goNamed(
                Routes.room,
                pathParameters: {'roomId': roomId},
              ),
            ),
            title: Text(_resolveRoomName(context, callService)),
          ),
        Expanded(child: body),
      ],
    );
  }
}
// coverage:ignore-end
