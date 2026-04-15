import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/utils/media_auth.dart';
import 'package:matrix/matrix.dart';

/// Displays a room's avatar with a colored-initial fallback.
///
/// Resolves the mxc:// avatar URL asynchronously via [getThumbnailUri]
/// and passes auth headers for authenticated media endpoints.
class RoomAvatarWidget extends StatefulWidget {
  const RoomAvatarWidget({
    required this.room, super.key,
    this.size = 44,
  });

  final Room room;
  final double size;

  @override
  State<RoomAvatarWidget> createState() => _RoomAvatarWidgetState();
}

class _RoomAvatarWidgetState extends State<RoomAvatarWidget> {
  String? _resolvedUrl;
  Uri? _lastAvatarUri;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveThumbnail());
  }

  @override
  void didUpdateWidget(RoomAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.room.avatar != _lastAvatarUri) {
      _resolvedUrl = null;
      unawaited(_resolveThumbnail());
    }
  }

  Future<void> _resolveThumbnail() async {
    final avatarUri = widget.room.avatar;
    _lastAvatarUri = avatarUri;
    if (avatarUri == null) return;
    try {
      final uri = await avatarUri.getThumbnailUri(
        widget.room.client,
        width: (widget.size * 2).toInt(),
        height: (widget.size * 2).toInt(),
      );
      if (mounted) setState(() => _resolvedUrl = uri.toString());
    } catch (e) {
      debugPrint('[Kohera] Failed to resolve room avatar thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.room.getLocalizedDisplayname();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '#';
    final bgColor = _colorFromString(name, cs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.28),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: _resolvedUrl!,
                httpHeaders:
                    mediaAuthHeaders(widget.room.client, _resolvedUrl!),
                imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
                fit: BoxFit.cover,
                placeholder: (_, __) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  textColor: Colors.white,
                  size: widget.size,
                ),
                errorWidget: (_, __, ___) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  textColor: Colors.white,
                  size: widget.size,
                ),
              )
            : _Fallback(
                initial: initial,
                bgColor: bgColor,
                textColor: Colors.white,
                size: widget.size,
              ),
      ),
    );
  }

  Color _colorFromString(String str, ColorScheme cs) {
    if (str.isEmpty) return cs.primaryContainer;
    final hash = str.codeUnits.fold<int>(0, (h, c) => h + c);
    final palette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.error,
      const Color(0xFF6750A4),
      const Color(0xFFB4846C),
      const Color(0xFF7C9A6E),
      const Color(0xFFC17B5F),
    ];
    return palette[hash % palette.length];
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.initial,
    required this.bgColor,
    required this.textColor,
    required this.size,
  });

  final String initial;
  final Color bgColor;
  final Color textColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: bgColor,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
