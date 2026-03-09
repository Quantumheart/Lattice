import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/features/calling/services/call_permission_service.dart';
import 'package:provider/provider.dart';

abstract class CallNavigator {
  static Future<void> startCall(
    BuildContext context, {
    required String roomId,
  }) async {
    final callService = context.read<CallService>();
    if (callService.callState != LatticeCallState.idle) return;

    final granted = await CallPermissionService.request();
    if (!granted || !context.mounted) return;

    await callService.joinCall(roomId);
    if (context.mounted && callService.callState == LatticeCallState.connected) {
      context.goNamed(
        Routes.call,
        pathParameters: {'roomId': roomId},
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
