import 'dart:async';

import 'package:kohera/features/calling/models/incoming_call_info.dart' as model;
import 'package:kohera/features/calling/services/ringtone_service.dart';

class CallRingingService {
  CallRingingService({RingtoneService? ringtoneService})
      : _ringtoneService = ringtoneService;

  RingtoneService? _ringtoneService;

  set ringtoneService(RingtoneService? service) => _ringtoneService = service;
  RingtoneService? get ringtoneServiceInstance => _ringtoneService;

  Timer? _ringingTimer;

  model.IncomingCallInfo? _incomingCall;
  model.IncomingCallInfo? get incomingCall => _incomingCall;

  final StreamController<model.IncomingCallInfo> _incomingCallController =
      StreamController<model.IncomingCallInfo>.broadcast();

  Stream<model.IncomingCallInfo> get incomingCallStream =>
      _incomingCallController.stream;

  void pushIncomingCall(model.IncomingCallInfo info) {
    _incomingCall = info;
    _incomingCallController.add(info);
  }

  void resetIncomingCall() => _incomingCall = null;

  void stopRinging() {
    _ringingTimer?.cancel();
    _ringingTimer = null;
    unawaited(_ringtoneService?.stop());
  }

  void playRingtone() {
    unawaited(_ringtoneService?.playRingtone());
  }

  void playDialtone() {
    unawaited(_ringtoneService?.playDialtone());
  }

  void startRingingTimer(Duration duration, void Function() onTimeout) {
    _ringingTimer?.cancel();
    _ringingTimer = Timer(duration, onTimeout);
  }

  void disposeRingtone() {
    unawaited(_ringtoneService?.dispose());
    _ringtoneService = null;
  }

  void dispose() {
    stopRinging();
    disposeRingtone();
    unawaited(_incomingCallController.close());
  }
}
