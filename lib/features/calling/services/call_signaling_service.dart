import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:matrix/matrix.dart';

// ── Signaling Events ───────────────────────────────────────

sealed class SignalingEvent {}

class LegacyCallAttempt extends SignalingEvent {
  LegacyCallAttempt({required this.roomId, required this.senderId});
  final String roomId;
  final String senderId;
}

// ── Call Signaling Service ─────────────────────────────────

class CallSignalingService {
  CallSignalingService({required Client client}) : _client = client;

  Client _client;

  void updateClient(Client client) => _client = client;

  StreamSubscription<Event>? _signalingEventSub;

  final _eventController = StreamController<SignalingEvent>.broadcast();
  Stream<SignalingEvent> get events => _eventController.stream;

  // ── Listener ───────────────────────────────────────────────

  void startSignalingListener() {
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub =
        _client.onTimelineEvent.stream.listen(_onTimelineEvent);
    debugPrint('[Kohera] Legacy call marker listener started');
  }

  void stopSignalingListener() {
    unawaited(_signalingEventSub?.cancel());
    _signalingEventSub = null;
  }

  void _onTimelineEvent(Event event) {
    if (event.type != kCallInvite) return;
    if (event.roomId == null) return;
    if (event.senderId == _client.userID) return;
    if (!event.room.isDirectChat) return;

    debugPrint(
      '[Kohera] Legacy m.call.invite from ${event.senderId} in ${event.roomId} '
      '(rendered as missed-call marker)',
    );
    _eventController.add(
      LegacyCallAttempt(roomId: event.roomId!, senderId: event.senderId),
    );
  }

  void dispose() {
    stopSignalingListener();
    unawaited(_eventController.close());
  }
}
