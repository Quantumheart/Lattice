import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:lattice/core/routing/route_names.dart';
import 'package:lattice/features/calling/services/call_service.dart';
import 'package:provider/provider.dart';

abstract class CallNavigator {
  static Future<void> startCall(
    BuildContext context, {
    required String roomId,
    required String displayName,
  }) async {
    final callService = context.read<CallService>();
    if (callService.isStarting) return;
    await callService.startCall(roomId, displayName);
    if (context.mounted && callService.hasActiveCall) {
      context.goNamed(
        Routes.call,
        pathParameters: {'roomId': roomId},
      );
    }
  }

  static Future<void> endCall(BuildContext context) async {
    final callService = context.read<CallService>();
    await callService.endCall();
    if (context.mounted) {
      context.goNamed(Routes.home);
    }
  }
}
