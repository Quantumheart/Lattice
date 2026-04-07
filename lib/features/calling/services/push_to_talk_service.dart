import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/calling/services/ringtone_service.dart';

class PushToTalkService extends ChangeNotifier {
  PushToTalkService({
    required CallService callService,
    required PreferencesService prefs,
    RingtoneService? ringtoneService,
  })  : _callService = callService,
        _prefs = prefs,
        _ringtone = ringtoneService {
    _callService.addListener(_onCallStateChanged);
    _prefs.addListener(_onPrefsChanged);
    _syncState();
  }

  final CallService _callService;
  final PreferencesService _prefs;
  final RingtoneService? _ringtone;
  bool _registered = false;
  bool _keyHeld = false;

  bool get isKeyHeld => _keyHeld;

  void _syncState() {
    final shouldListen = _prefs.pushToTalkEnabled &&
        _callService.callState == LatticeCallState.connected;

    if (shouldListen && !_registered) {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
      _registered = true;
      if (_callService.isMicEnabled) {
        unawaited(_callService.toggleMicrophone());
      }
    } else if (!shouldListen && _registered) {
      _unregister();
    }
  }

  void _unregister() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _registered = false;
    if (_keyHeld) {
      _keyHeld = false;
      notifyListeners();
    }
  }

  void _onCallStateChanged() => _syncState();

  void _onPrefsChanged() => _syncState();

  bool _onKeyEvent(KeyEvent event) {
    final targetKeyId = _prefs.pushToTalkKeyId;
    if (event.logicalKey.keyId != targetKeyId) return false;

    if (event is KeyDownEvent && !_keyHeld) {
      _keyHeld = true;
      if (_prefs.pttSoundEnabled) unawaited(_ringtone?.playPTTOn());
      if (!_callService.isMicEnabled) {
        unawaited(_callService.toggleMicrophone());
      }
      notifyListeners();
      return true;
    }

    if (event is KeyUpEvent && _keyHeld) {
      _keyHeld = false;
      if (_prefs.pttSoundEnabled) unawaited(_ringtone?.playPTTOff());
      if (_callService.isMicEnabled) {
        unawaited(_callService.toggleMicrophone());
      }
      notifyListeners();
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _callService.removeListener(_onCallStateChanged);
    _prefs.removeListener(_onPrefsChanged);
    if (_registered) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    }
    super.dispose();
  }
}
