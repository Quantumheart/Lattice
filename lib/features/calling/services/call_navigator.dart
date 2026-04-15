import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/features/calling/models/incoming_call_info.dart' as model;
import 'package:kohera/features/calling/services/call_permission_service.dart';
import 'package:provider/provider.dart';

// coverage:ignore-start
abstract class CallNavigator {
  static Future<void> startCall(
    BuildContext context, {
    required String roomId,
    model.CallType type = model.CallType.voice,
  }) async {
    final callService = context.read<CallService>();
    if (callService.callState != KoheraCallState.idle &&
        callService.callState != KoheraCallState.failed) {
      return;
    }

    final granted = await CallPermissionService.request();
    if (!granted || !context.mounted) return;

    final room = callService.client.getRoomById(roomId);
    final isDm = room?.isDirectChat ?? false;

    if (isDm) {
      await callService.initiateCall(roomId, type: type);
    } else {
      unawaited(callService.joinCall(roomId));
    }

    if (context.mounted) {
      context.pushOrGo(
        Routes.call,
        pathParameters: {'roomId': roomId},
      );
    }
  }

  static void acceptIncoming(BuildContext context, {String? roomId}) {
    final id = roomId ?? context.read<CallService>().activeCallRoomId;
    if (id != null && context.mounted) {
      context.pushOrGo(
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
// coverage:ignore-end
