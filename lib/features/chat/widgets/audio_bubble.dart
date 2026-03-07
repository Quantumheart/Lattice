import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lattice/core/utils/format_duration.dart';
import 'package:lattice/core/utils/format_file_size.dart';
import 'package:lattice/core/utils/media_cache.dart';
import 'package:lattice/features/chat/services/media_playback_service.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

// ── Audio bubble (waveform + seek + play/pause) ───────────────

const _maxFileSizeBytes = 104857600;
const _barCount = 40;

class AudioBubble extends StatefulWidget {
  const AudioBubble({required this.event, required this.isMe, super.key});

  final Event event;
  final bool isMe;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

enum _AudioState { initial, loading, ready, error }

class _AudioBubbleState extends State<AudioBubble> {
  _AudioState _state = _AudioState.initial;
  Player? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;
  late final MediaPlaybackService _playbackService;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _bars = _generateBars(widget.event.eventId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackService = context.read<MediaPlaybackService>();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    if (_player != null) {
      _playbackService.unregisterPlayer(widget.event.eventId);
      _player!.dispose();
    }
    super.dispose();
  }

  bool get _tooLarge {
    final size = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('size');
    return size != null && size > _maxFileSizeBytes;
  }

  bool get _pendingSend =>
      widget.event.status == EventStatus.sending ||
      widget.event.status == EventStatus.error;

  Future<void> _initAndPlay() async {
    if (_tooLarge || _pendingSend) return;
    setState(() => _state = _AudioState.loading);

    try {
      final media = await MediaCache.resolve(widget.event);
      if (!mounted) return;

      _player = Player();
      _subs.add(_player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _playing = playing);
      }),);
      _subs.add(_player!.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),);
      _subs.add(_player!.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),);
      _subs.add(_player!.stream.completed.listen((completed) {
        if (completed && mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),);

      await _player!.open(media);
      if (!mounted) return;

      _playbackService.registerPlayer(
            widget.event.eventId,
            _player!,
          );
      setState(() => _state = _AudioState.ready);
    } catch (e) {
      debugPrint('[Lattice] Audio playback failed: $e');
      if (mounted) setState(() => _state = _AudioState.error);
    }
  }

  void _togglePlayPause() {
    if (_player == null) return;
    if (_playing) {
      _player!.pause();
    } else {
      _playbackService.registerPlayer(
            widget.event.eventId,
            _player!,
          );
      _player!.play();
    }
  }

  void _seek(double fraction) {
    if (_player == null || _duration == Duration.zero) return;
    final target = Duration(
      milliseconds: (fraction * _duration.inMilliseconds).round(),
    );
    _player!.seek(target);
  }

  void _retry() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _player?.dispose();
    _player = null;
    _initAndPlay();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = widget.isMe ? cs.onPrimary : cs.onSurface;
    final accent = widget.isMe ? cs.onPrimary : cs.primary;
    final muted = foreground.withValues(alpha: 0.3);

    if (_tooLarge) {
      return _buildFileFallback(foreground, tt);
    }

    return SizedBox(
      width: 260,
      child: Row(
        children: [
          _buildPlayButton(foreground, accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (waveformContext) {
                    void seekFromOffset(double dx) {
                      final box =
                          waveformContext.findRenderObject()! as RenderBox;
                      _seek((dx / box.size.width).clamp(0.0, 1.0));
                    }

                    return GestureDetector(
                      onTapDown: (d) => seekFromOffset(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) =>
                          seekFromOffset(d.localPosition.dx),
                      child: CustomPaint(
                        size: const Size(double.infinity, 32),
                        painter: _WaveformPainter(
                          bars: _bars,
                          progress: _duration.inMilliseconds > 0
                              ? _position.inMilliseconds /
                                  _duration.inMilliseconds
                              : 0.0,
                          activeColor: accent,
                          inactiveColor: muted,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(
                      _state == _AudioState.ready ? _position : _infoDuration,),
                  style: tt.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(Color foreground, Color accent) {
    switch (_state) {
      case _AudioState.initial:
        return IconButton(
          onPressed: _pendingSend ? null : _initAndPlay,
          icon: Icon(Icons.play_arrow_rounded,
              color: _pendingSend
                  ? foreground.withValues(alpha: 0.3)
                  : foreground,),
          style: IconButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.15),
          ),
        );
      case _AudioState.loading:
        return const SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _AudioState.ready:
        return IconButton(
          onPressed: _togglePlayPause,
          icon: Icon(
            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: foreground,
          ),
          style: IconButton.styleFrom(
            backgroundColor: accent.withValues(alpha: 0.15),
          ),
        );
      case _AudioState.error:
        return IconButton(
          onPressed: _retry,
          icon: Icon(Icons.refresh_rounded, color: foreground),
          style: IconButton.styleFrom(
            backgroundColor: foreground.withValues(alpha: 0.1),
          ),
        );
    }
  }

  Widget _buildFileFallback(Color foreground, TextTheme tt) {
    final size = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('size');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.audiotrack_rounded,
            size: 28, color: foreground.withValues(alpha: 0.7),),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.event.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  tt.bodyMedium?.copyWith(color: foreground, fontWeight: FontWeight.w500),
            ),
            if (size != null)
              Text(
                formatFileSize(size),
                style: tt.bodySmall?.copyWith(
                  color: foreground.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Duration get _infoDuration {
    final ms = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('duration');
    return ms != null ? Duration(milliseconds: ms) : Duration.zero;
  }

  static List<double> _generateBars(String seed) {
    final hash = seed.hashCode;
    final rng = Random(hash);
    return List.generate(_barCount, (_) => 0.15 + rng.nextDouble() * 0.85);
  }
}

// ── Waveform painter ──────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (bars.length * 2 - 1);
    final maxHeight = size.height;

    for (var i = 0; i < bars.length; i++) {
      final x = i * barWidth * 2;
      final barHeight = bars[i] * maxHeight;
      final y = (maxHeight - barHeight) / 2;
      final fraction = bars.length > 1 ? i / (bars.length - 1) : 0.0;
      final paint = Paint()
        ..color = fraction <= progress ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
