import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Displays a grid of images/videos and a list of files shared in a room.
/// Loads media lazily using room search with pagination.
class SharedMediaSection extends StatefulWidget {
  const SharedMediaSection({super.key, required this.room});

  final Room room;

  @override
  State<SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<SharedMediaSection> {
  final List<Event> _mediaEvents = [];
  String? _nextBatch;
  bool _loading = false;
  bool _hasMore = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(SharedMediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _generation++;
      _mediaEvents.clear();
      _nextBatch = null;
      _hasMore = true;
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    if (_loading) return;
    setState(() => _loading = true);
    final gen = _generation;

    try {
      final result = await widget.room.searchEvents(
        searchFunc: (event) {
          final mt = event.messageType;
          return mt == MessageTypes.Image ||
              mt == MessageTypes.Video ||
              mt == MessageTypes.File ||
              mt == MessageTypes.Audio;
        },
        nextBatch: _nextBatch,
        limit: 20,
      );

      if (!mounted || gen != _generation) return;
      setState(() {
        _mediaEvents.addAll(result.events);
        _nextBatch = result.nextBatch;
        _hasMore = result.nextBatch != null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Lattice] Load media failed: $e');
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final images = _mediaEvents
        .where((e) =>
            e.messageType == MessageTypes.Image ||
            e.messageType == MessageTypes.Video)
        .toList();
    final files = _mediaEvents
        .where((e) =>
            e.messageType == MessageTypes.File ||
            e.messageType == MessageTypes.Audio)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'SHARED MEDIA',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading && _mediaEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_mediaEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No shared media yet',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        else ...[
          // Image/video grid
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: images.map((e) => _MediaThumbnail(event: e)).toList(),
              ),
            ),

          // File list
          for (final file in files)
            ListTile(
              dense: true,
              leading: Icon(
                file.messageType == MessageTypes.Audio
                    ? Icons.audiotrack_rounded
                    : Icons.insert_drive_file_rounded,
                color: cs.onSurfaceVariant,
              ),
              title: Text(
                file.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium,
              ),
              subtitle: Text(
                _formatFileSize((file.infoMap['size'] as num?)?.toInt()),
                style: tt.bodySmall,
              ),
            ),

          // Load more
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _loadMedia,
                        child: const Text('Load more'),
                      ),
              ),
            ),
        ],
      ],
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Returns auth headers only if [url] points to the same host as the
/// homeserver, preventing token leakage to federated media servers.
Map<String, String>? _authHeaders(Client client, String url) {
  try {
    final uri = Uri.parse(url);
    final homeserver = client.homeserver;
    if (homeserver != null && uri.host == homeserver.host) {
      return {'authorization': 'Bearer ${client.accessToken}'};
    }
  } catch (_) {}
  return null;
}

// ── Media thumbnail ────────────────────────────────────────────

class _MediaThumbnail extends StatefulWidget {
  const _MediaThumbnail({required this.event});

  final Event event;

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<_MediaThumbnail> {
  Uint8List? _thumbnailBytes;
  String? _thumbnailUrl;
  bool _loading = true;
  bool _loadStarted = false;

  @override
  void initState() {
    super.initState();
    // Defer loading to avoid firing all thumbnails simultaneously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loadStarted) {
        _loadStarted = true;
        _loadThumbnail();
      }
    });
  }

  Future<void> _loadThumbnail() async {
    try {
      if (widget.event.isAttachmentEncrypted) {
        // Encrypted: download and decrypt
        final file = await widget.event.downloadAndDecryptAttachment(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _thumbnailBytes = file.bytes;
            _loading = false;
          });
        }
      } else {
        // Unencrypted: resolve URI
        final uri = await widget.event.getAttachmentUri(
          getThumbnail: true,
          width: 200,
          height: 200,
          method: ThumbnailMethod.crop,
        );
        if (mounted) {
          setState(() {
            _thumbnailUrl = uri?.toString();
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Thumbnail load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: cs.surfaceContainerHighest,
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _thumbnailBytes != null
                  ? Image.memory(_thumbnailBytes!, fit: BoxFit.cover)
                  : _thumbnailUrl != null
                      ? Image.network(
                          _thumbnailUrl!,
                          fit: BoxFit.cover,
                          headers: _authHeaders(
                            widget.event.room.client,
                            _thumbnailUrl!,
                          ),
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : Icon(
                          Icons.image_rounded,
                          color: cs.onSurfaceVariant,
                        ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: _FullImageView(event: widget.event),
      ),
    );
  }
}

// ── Full image viewer ──────────────────────────────────────────

class _FullImageView extends StatefulWidget {
  const _FullImageView({required this.event});

  final Event event;

  @override
  State<_FullImageView> createState() => _FullImageViewState();
}

class _FullImageViewState extends State<_FullImageView> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFullImage();
  }

  Future<void> _loadFullImage() async {
    try {
      if (widget.event.isAttachmentEncrypted) {
        final file = await widget.event.downloadAndDecryptAttachment();
        if (mounted) {
          setState(() {
            _imageBytes = file.bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.event.getAttachmentUri();
        if (mounted) {
          setState(() {
            _imageUrl = uri?.toString();
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Full image load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 300,
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final image = _imageBytes != null
        ? Image.memory(_imageBytes!, fit: BoxFit.contain)
        : _imageUrl != null
            ? Image.network(
                _imageUrl!,
                fit: BoxFit.contain,
                headers: _authHeaders(
                  widget.event.room.client,
                  _imageUrl!,
                ),
                errorBuilder: (_, __, ___) => SizedBox(
                  width: 300,
                  height: 300,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: cs.onSurfaceVariant,
                      size: 48,
                    ),
                  ),
                ),
              )
            : const SizedBox(
                width: 300,
                height: 300,
                child: Center(child: Text('Failed to load image')),
              );

    return InteractiveViewer(child: image);
  }
}
