import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

class ParticipantTile extends StatefulWidget {
  const ParticipantTile({required this.participant, super.key});

  final CallParticipant participant;

  @override
  State<ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<ParticipantTile> {
  static const _minAudioBarWidth = 4.0;
  static const _maxAudioBarWidth = 20.0;
  static const _audioLevelThreshold = 0.05;

  rtc.RTCVideoRenderer? _renderer;
  int _setupGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_setupRenderer());
  }

  @override
  void didUpdateWidget(covariant ParticipantTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participant.mediaStream != oldWidget.participant.mediaStream) {
      unawaited(_setupRenderer());
    }
  }

  Future<void> _setupRenderer() async {
    final generation = ++_setupGeneration;
    final stream = widget.participant.mediaStream;
    if (stream == null) {
      if (_renderer != null) {
        _renderer!.srcObject = null;
        await _renderer!.dispose();
        _renderer = null;
        if (mounted && generation == _setupGeneration) setState(() {});
      }
      return;
    }

    _renderer ??= rtc.RTCVideoRenderer();
    await _renderer!.initialize();
    if (generation != _setupGeneration) return;
    _renderer!.srcObject = stream;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _renderer?.srcObject = null;
    unawaited(_renderer?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.participant.isSpeaking ? cs.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: widget.participant.isSpeaking
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoArea(context),
            _buildBottomOverlay(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final livekitTrack = widget.participant.videoTrack;
    if (livekitTrack != null) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: livekit.VideoTrackRenderer(
          livekitTrack,
          fit: livekit.VideoViewFit.cover,
        ),
      );
    }

    if (_renderer?.srcObject != null) {
      return ColoredBox(
        color: cs.surfaceContainerHighest,
        child: rtc.RTCVideoView(
          _renderer!,
          objectFit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          mirror: widget.participant.isLocal,
        ),
      );
    }

    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: CircleAvatar(
          radius: 32,
          backgroundColor: cs.primaryContainer,
          child: Text(
            widget.participant.displayName.isNotEmpty
                ? widget.participant.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 28,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showAudioBar = widget.participant.audioLevel > _audioLevelThreshold;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, cs.scrim.withValues(alpha: 0.54)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (showAudioBar) ...[
                Container(
                  width: _minAudioBarWidth +
                      widget.participant.audioLevel *
                          (_maxAudioBarWidth - _minAudioBarWidth),
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  widget.participant.isLocal
                      ? '${widget.participant.displayName} (You)'
                      : widget.participant.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.participant.isMuted)
                const Icon(Icons.mic_off, size: 14, color: Colors.redAccent),
            ],
          ),
        ),
      ),
    );
  }
}
