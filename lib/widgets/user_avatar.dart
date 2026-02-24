import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/media_auth.dart';

/// Displays a user's Matrix avatar with a colored-initial fallback.
///
/// Resolves the mxc:// [avatarUrl] asynchronously via [getThumbnailUri]
/// and passes auth headers for authenticated media endpoints.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.client,
    this.avatarUrl,
    this.userId,
    this.size = 44,
  });

  final Client client;
  final Uri? avatarUrl;
  final String? userId;
  final double size;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _resolvedUrl = null;
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    final avatarUrl = widget.avatarUrl;
    if (avatarUrl == null) return;
    try {
      final uri = await avatarUrl.getThumbnailUri(
        widget.client,
        width: (widget.size * 2).toInt(),
        height: (widget.size * 2).toInt(),
      );
      if (mounted) setState(() => _resolvedUrl = uri.toString());
    } catch (e) {
      debugPrint('[Lattice] Failed to resolve avatar thumbnail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = _userInitial(widget.userId);
    final bgColor = _colorFromString(widget.userId ?? '', cs);

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _resolvedUrl != null
            ? CachedNetworkImage(
                imageUrl: _resolvedUrl!,
                httpHeaders: mediaAuthHeaders(widget.client, _resolvedUrl!),
                fit: BoxFit.cover,
                placeholder: (_, __) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  size: widget.size,
                ),
                errorWidget: (_, __, ___) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  size: widget.size,
                ),
              )
            : _Fallback(
                initial: initial,
                bgColor: bgColor,
                size: widget.size,
              ),
      ),
    );
  }

  static String _userInitial(String? userId) {
    if (userId != null && userId.length > 1) return userId[1].toUpperCase();
    return (userId ?? '?')[0].toUpperCase();
  }

  static Color _colorFromString(String str, ColorScheme cs) {
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
    required this.size,
  });

  final String initial;
  final Color bgColor;
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
          color: Colors.white,
        ),
      ),
    );
  }
}
