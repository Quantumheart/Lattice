import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../utils/media_auth.dart';
import '../full_image_view.dart';

// ── Image bubble (async URI resolution) ──────────────────────

class ImageBubble extends StatefulWidget {
  const ImageBubble({super.key, required this.event});

  final Event event;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ImageBubble old) {
    super.didUpdateWidget(old);
    if (old.event.eventId != widget.event.eventId) {
      _imageBytes = null;
      _imageUrl = null;
      _loading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      if (widget.event.isAttachmentEncrypted) {
        final file = await widget.event.downloadAndDecryptAttachment(
          getThumbnail: true,
        );
        if (mounted) {
          setState(() {
            _imageBytes = file.bytes;
            _loading = false;
          });
        }
      } else {
        final uri = await widget.event.getAttachmentUri(
          getThumbnail: true,
          width: 280,
          height: 260,
          method: ThumbnailMethod.scale,
        );
        if (mounted) {
          setState(() {
            _imageUrl = uri?.toString();
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Lattice] Image bubble load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => showFullImageDialog(context, widget.event),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
          child: _loading
              ? Container(
                  height: 80,
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _imageBytes != null
                  ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? Image.network(
                          _imageUrl!,
                          fit: BoxFit.cover,
                          headers: mediaAuthHeaders(
                            widget.event.room.client,
                            _imageUrl!,
                          ),
                          errorBuilder: (_, __, ___) => Container(
                            height: 80,
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        )
                      : Container(
                          height: 80,
                          color: cs.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
        ),
      ),
    );
  }
}
