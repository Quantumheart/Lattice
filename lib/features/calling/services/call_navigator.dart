import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/models/incoming_call_info.dart' as model;
import 'package:lattice/features/calling/services/call_permission_service.dart';
import 'package:provider/provider.dart';

abstract class CallNavigator {
  static Future<void> startCall(
    BuildContext context, {
    required String roomId,
    model.CallType type = model.CallType.voice,
  }) async {
    final callService = context.read<CallService>();
    if (callService.callState != LatticeCallState.idle &&
        callService.callState != LatticeCallState.failed) {
      return;
    }

    final granted = await CallPermissionService.request();
    if (!granted || !context.mounted) return;

    final room = callService.client.getRoomById(roomId);
    final isDm = room?.isDirectChat ?? false;

    if (isDm) {
      await callService.initiateCall(roomId, type: type);
      if (context.mounted && callService.callState == LatticeCallState.connected) {
        context.goNamed(
          Routes.call,
          pathParameters: {'roomId': roomId},
        );
      }
    } else {
      await callService.joinCall(roomId);
      if (context.mounted && callService.callState == LatticeCallState.connected) {
        context.goNamed(
          Routes.call,
          pathParameters: {'roomId': roomId},
        );
      }
    }
  }

  static void acceptIncoming(BuildContext context, {String? roomId}) {
    final id = roomId ?? context.read<CallService>().activeCallRoomId;
    if (id != null && context.mounted) {
      context.goNamed(
        Routes.call,
        pathParameters: {'roomId': id},
      );
    }
  }

  static Future<void> endCall(BuildContext context) async {
    final callService = context.read<CallService>();
    await callService.leaveCall();
    if (context.mounted) {
      context.goNamed(Routes.home);
    }
  }
}
