import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Displays a room's avatar with a colored-initial fallback.
class RoomAvatarWidget extends StatelessWidget {
  const RoomAvatarWidget({
    super.key,
    required this.room,
    this.size = 44,
  });

  final Room room;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = room.avatar?.getThumbnailUri(
      room.client,
      width: (size * 2).toInt(),
      height: (size * 2).toInt(),
    );

    final name = room.getLocalizedDisplayname();
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : '#';

    final bgColor = _colorFromString(name, cs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(
        width: size,
        height: size,
        child: avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: avatarUrl.toString(),
                fit: BoxFit.cover,
                placeholder: (_, __) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  textColor: Colors.white,
                  size: size,
                ),
                errorWidget: (_, __, ___) => _Fallback(
                  initial: initial,
                  bgColor: bgColor,
                  textColor: Colors.white,
                  size: size,
                ),
              )
            : _Fallback(
                initial: initial,
                bgColor: bgColor,
                textColor: Colors.white,
                size: size,
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
