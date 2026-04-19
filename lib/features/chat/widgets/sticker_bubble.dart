import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:matrix/matrix.dart';

// coverage:ignore-start

class StickerBubble extends StatefulWidget {
  const StickerBubble({
    required this.event,
    required this.isMe,
    super.key,
  });

  final Event event;
  final bool isMe;

  @override
  State<StickerBubble> createState() => _StickerBubbleState();
}

class _StickerBubbleState extends State<StickerBubble> {
  static const double _maxSize = 180;

  Uint8List? _imageBytes;
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSticker());
  }

  @override
  void didUpdateWidget(StickerBubble old) {
    super.didUpdateWidget(old);
    if (old.event.eventId != widget.event.eventId) {
      _imageBytes = null;
      _imageUrl = null;
      _loading = true;
      unawaited(_loadSticker());
    }
  }

  Future<void> _loadSticker() async {
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
        final uri = await widget.event.getAttachmentUri(
          width: _maxSize.toInt() * 2,
          height: _maxSize.toInt() * 2,
        );
        if (mounted) {
          setState(() {
            _imageUrl = uri?.toString();
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Sticker load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.event.content.tryGet<String>('body') ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment:
            widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: _maxSize,
              maxWidth: _maxSize,
            ),
            child: _loading
                ? const SizedBox(
                    width: 80,
                    height: 80,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _imageBytes != null
                    ? Image.memory(
                        _imageBytes!,
                        fit: BoxFit.contain,
                        semanticLabel: body,
                      )
                    : _imageUrl != null
                        ? Image.network(
                            _imageUrl!,
                            fit: BoxFit.contain,
                            semanticLabel: body,
                            headers: mediaAuthHeaders(
                              widget.event.room.client,
                              _imageUrl!,
                            ),
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                            ),
                          )
                        : const Icon(Icons.broken_image_outlined, size: 48),
          ),
        ],
      ),
    );
  }
}
// coverage:ignore-end
