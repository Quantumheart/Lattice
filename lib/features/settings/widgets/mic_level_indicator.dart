import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:record/record.dart';

class MicLevelIndicator extends StatefulWidget {
  const MicLevelIndicator({
    this.deviceId,
    this.loopbackEnabled = false,
    this.pttMuted = false,
    super.key,
  });

  final String? deviceId;
  final bool loopbackEnabled;
  final bool pttMuted;

  @override
  State<MicLevelIndicator> createState() => _MicLevelIndicatorState();
}

class _MicLevelIndicatorState extends State<MicLevelIndicator> {
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _level = 0;
  String? _error;

  rtc.RTCPeerConnection? _localPc;
  rtc.RTCPeerConnection? _remotePc;
  rtc.MediaStream? _loopbackStream;

  @override
  void initState() {
    super.initState();
    unawaited(_startCapture());
  }

  bool get _shouldLoopback => widget.loopbackEnabled && !widget.pttMuted;

  @override
  void didUpdateWidget(MicLevelIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      unawaited(_restartCapture());
      if (_shouldLoopback) {
        unawaited(_restartLoopback());
      }
    }
    final wasLooping = oldWidget.loopbackEnabled && !oldWidget.pttMuted;
    if (wasLooping != _shouldLoopback) {
      if (_shouldLoopback) {
        unawaited(_startLoopback());
      } else {
        unawaited(_stopLoopback());
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stopCapture());
    unawaited(_stopLoopback());
    super.dispose();
  }

  // ── Amplitude capture ──────────────────────────────────────

  Future<void> _startCapture() async {
    try {
      _recorder = AudioRecorder();
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        if (mounted) setState(() => _error = 'Microphone access denied');
        return;
      }

      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
        device: widget.deviceId != null
            ? InputDevice(id: widget.deviceId!, label: '')
            : null,
      );
      await _recorder!.startStream(config);

      _amplitudeSub = _recorder!
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (!mounted) return;
        final normalized = _dbToLinear(amp.current);
        setState(() => _level = normalized);
      });
    } catch (e) {
      debugPrint('[Lattice] Mic level capture failed: $e');
      if (mounted) setState(() => _error = 'Microphone access denied');
    }
  }

  double _dbToLinear(double dbFS) {
    if (dbFS <= -60) return 0;
    if (dbFS >= 0) return 1;
    return math.pow(10, dbFS / 20).toDouble();
  }

  Future<void> _stopCapture() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _recorder?.stop();
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
  }

  Future<void> _restartCapture() async {
    await _stopCapture();
    setState(() {
      _level = 0;
      _error = null;
    });
    await _startCapture();
  }

  // ── Loopback via WebRTC peer connection ────────────────────

  Future<void> _startLoopback() async {
    try {
      final constraints = <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': false,
          'noiseSuppression': false,
          if (widget.deviceId != null) 'deviceId': widget.deviceId,
        },
        'video': false,
      };
      _loopbackStream =
          await rtc.navigator.mediaDevices.getUserMedia(constraints);

      final config = <String, dynamic>{
        'iceServers': <dynamic>[],
        'sdpSemantics': 'unified-plan',
      };
      _localPc = await rtc.createPeerConnection(config);
      _remotePc = await rtc.createPeerConnection(config);

      _localPc!.onIceCandidate = (candidate) {
        unawaited(_remotePc?.addCandidate(candidate));
      };
      _remotePc!.onIceCandidate = (candidate) {
        unawaited(_localPc?.addCandidate(candidate));
      };

      for (final track in _loopbackStream!.getAudioTracks()) {
        await _localPc!.addTrack(track, _loopbackStream!);
      }

      final offer = await _localPc!.createOffer();
      await _localPc!.setLocalDescription(offer);
      await _remotePc!.setRemoteDescription(offer);

      final answer = await _remotePc!.createAnswer();
      await _remotePc!.setLocalDescription(answer);
      await _localPc!.setRemoteDescription(answer);
    } catch (e) {
      debugPrint('[Lattice] Loopback failed: $e');
      await _stopLoopback();
    }
  }

  Future<void> _stopLoopback() async {
    try {
      await _localPc?.close();
      await _remotePc?.close();
      _loopbackStream?.getAudioTracks().forEach((t) => t.stop());
      await _loopbackStream?.dispose();
    } catch (_) {}
    _localPc = null;
    _remotePc = null;
    _loopbackStream = null;
  }

  Future<void> _restartLoopback() async {
    await _stopLoopback();
    await _startLoopback();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.mic_off_rounded, size: 16, color: cs.error),
            const SizedBox(width: 8),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ],
        ),
      );
    }

    final displayLevel = widget.pttMuted ? 0.0 : _level;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mic level',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: displayLevel.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              displayLevel > 0 ? Colors.green : cs.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}
