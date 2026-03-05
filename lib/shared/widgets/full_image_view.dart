import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/core/utils/media_auth.dart';
import 'package:lattice/shared/widgets/media_viewer_shell.dart';

void showFullImageDialog(BuildContext context, Event event) {
  showMediaViewer(
    context,
    event: event,
    child: _FullImageContent(event: event),
  );
}

// ── Full image viewer ──────────────────────────────────────────

class _FullImageContent extends StatefulWidget {
  const _FullImageContent({required this.event});

  final Event event;

  @override
  State<_FullImageContent> createState() => _FullImageContentState();
}

class _FullImageContentState extends State<_FullImageContent> {
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
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final image = _imageBytes != null
        ? Image.memory(_imageBytes!, fit: BoxFit.contain)
        : _imageUrl != null
            ? Image.network(
                _imageUrl!,
                fit: BoxFit.contain,
                headers: mediaAuthHeaders(
                  widget.event.room.client,
                  _imageUrl!,
                ),
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: cs.onSurfaceVariant,
                    size: 48,
                  ),
                ),
              )
            : const Center(child: Text('Failed to load image'));

    return InteractiveViewer(child: image);
  }
}
