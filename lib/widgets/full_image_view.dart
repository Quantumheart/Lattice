import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../utils/media_auth.dart';

/// Opens a dialog displaying the full-resolution image for [event].
void showFullImageDialog(BuildContext context, Event event) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: FullImageView(event: event),
    ),
  );
}

// ── Full image viewer ──────────────────────────────────────────

class FullImageView extends StatefulWidget {
  const FullImageView({super.key, required this.event});

  final Event event;

  @override
  State<FullImageView> createState() => FullImageViewState();
}

class FullImageViewState extends State<FullImageView> {
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
                headers: mediaAuthHeaders(
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
