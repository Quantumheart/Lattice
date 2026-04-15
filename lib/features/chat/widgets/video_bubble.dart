import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/format_duration.dart';
import 'package:kohera/core/utils/format_file_size.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:kohera/core/utils/media_cache.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/full_video_view.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

// ── Video bubble (thumbnail → inline player) ──────────────────

const _maxFileSizeBytes = 104857600;

class VideoBubble extends StatefulWidget {
  const VideoBubble({required this.event, required this.isMe, super.key});

  final Event event;
  final bool isMe;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

enum _VideoState { initial, loadingThumb, loadingVideo, playing, error }

class _VideoBubbleState extends State<VideoBubble> {
  _VideoState _state = _VideoState.initial;
  Uint8List? _thumbBytes;
  String? _thumbUrl;
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = false;
  late final MediaPlaybackService _playbackService;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadThumbnail());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackService = context.read<MediaPlaybackService>();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    if (_player != null) {
      _playbackService.unregisterPlayer(widget.event.eventId);
      unawaited(_player!.dispose());
    }
    super.dispose();
  }

  bool get _tooLarge {
    final size = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('size');
    return size != null && size > _maxFileSizeBytes;
  }

  Future<void> _loadThumbnail() async {
    setState(() => _state = _VideoState.loadingThumb);
    try {
      if (widget.event.isAttachmentEncrypted) {
        final file = await widget.event.downloadAndDecryptAttachment(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _thumbBytes = file.bytes;
            _state = _VideoState.initial;
          });
        }
      } else {
        final uri = await widget.event.getAttachmentUri(
          getThumbnail: true,
          width: 280,
          height: 260,
        );
        if (mounted) {
          setState(() {
            _thumbUrl = uri?.toString();
            _state = _VideoState.initial;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Video thumbnail load failed: $e');
      if (mounted) setState(() => _state = _VideoState.initial);
    }
  }

  Future<void> _initPlayer() async {
    if (_tooLarge) return;
    setState(() => _state = _VideoState.loadingVideo);

    try {
      final media = await MediaCache.resolve(widget.event);
      if (!mounted) return;

      _player = Player();
      _controller = VideoController(_player!);

      _subs.add(_player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),);
      _subs.add(_player!.stream.completed.listen((completed) {
        if (completed && mounted) {
          unawaited(_player!.seek(Duration.zero));
          unawaited(_player!.pause());
        }
      }),);

      await _player!.open(media);
      if (!mounted) return;

      _playbackService.registerPlayer(
            widget.event.eventId,
            _player!,
          );
      setState(() => _state = _VideoState.playing);
    } catch (e) {
      debugPrint('[Kohera] Video playback failed: $e');
      if (mounted) setState(() => _state = _VideoState.error);
    }
  }

  void _retry() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    if (_player != null) unawaited(_player!.dispose());
    _player = null;
    _controller = null;
    unawaited(_initPlayer());
  }

  void _openFullscreen() {
    if (_player == null || _controller == null) return;
    showFullVideoDialog(context, event: widget.event, player: _player!, controller: _controller!);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = widget.isMe ? cs.onPrimary : cs.onSurface;

    if (_tooLarge) {
      return _buildFileFallback(foreground, tt);
    }

    if (_state == _VideoState.playing && _controller != null) {
      return _buildInlinePlayer(cs);
    }

    return _buildThumbnailPreview(cs, foreground);
  }

  Widget _buildThumbnailPreview(ColorScheme cs, Color foreground) {
    final durationMs = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('duration');
    final durationLabel = durationMs != null
        ? formatDuration(Duration(milliseconds: durationMs))
        : null;

    Widget thumb;
    if (_thumbBytes != null) {
      thumb = Image.memory(_thumbBytes!, fit: BoxFit.cover, width: 280, height: 180);
    } else if (_thumbUrl != null) {
      thumb = Image.network(
        _thumbUrl!,
        fit: BoxFit.cover,
        width: 280,
        height: 180,
        headers: mediaAuthHeaders(widget.event.room.client, _thumbUrl!),
        errorBuilder: (_, __, ___) => _placeholderThumb(cs),
      );
    } else {
      thumb = _placeholderThumb(cs);
    }

    return GestureDetector(
      onTap: _state == _VideoState.loadingVideo
          ? null
          : _state == _VideoState.error
              ? _retry
              : _initPlayer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 260),
          child: Stack(
            alignment: Alignment.center,
            children: [
              thumb,
              if (_state == _VideoState.loadingVideo)
                const CircularProgressIndicator(strokeWidth: 2)
              else if (_state == _VideoState.error)
                Icon(Icons.error_outline_rounded,
                    size: 40, color: cs.error,)
              else
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              if (durationLabel != null)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      durationLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      unawaited(_player!.pause());
    } else {
      _playbackService.registerPlayer(widget.event.eventId, _player!);
      unawaited(_player!.play());
    }
  }

  Widget _buildInlinePlayer(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 260),
        child: Video(
          controller: _controller!,
          controls: (state) => GestureDetector(
            onTap: _togglePlayPause,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox.expand(),
                if (!_isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filled(
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileFallback(Color foreground, TextTheme tt) {
    final size = widget.event.content
        .tryGet<Map<String, Object?>>('info')
        ?.tryGet<int>('size');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_rounded,
            size: 28, color: foreground.withValues(alpha: 0.7),),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.event.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w500),
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
        ),
      ],
    );
  }

  Widget _placeholderThumb(ColorScheme cs) {
    return Container(
      width: 280,
      height: 180,
      color: cs.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.videocam_rounded, size: 40)),
    );
  }

}
