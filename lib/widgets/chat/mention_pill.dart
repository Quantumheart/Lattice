import 'package:flutter/material.dart';

/// The type of Matrix mention represented by a [MentionPill].
enum MentionType { user, room }

/// An inline pill chip for Matrix user or room mentions.
///
/// Used as a [WidgetSpan] inside [Text.rich] to visually distinguish
/// `@user:server` and `#room:server` mentions from regular links.
class MentionPill extends StatelessWidget {
  const MentionPill({
    super.key,
    required this.displayName,
    required this.matrixId,
    required this.type,
    required this.isMe,
    required this.style,
    this.onTap,
  });

  /// The resolved display name shown inside the pill.
  final String displayName;

  /// The raw Matrix identifier (e.g. `@alice:example.com`).
  final String matrixId;

  /// Whether this is a user or room mention.
  final MentionType type;

  /// Whether the pill is inside a "sent by me" bubble.
  final bool isMe;

  /// The surrounding text style (used for font size).
  final TextStyle style;

  /// Called when the pill is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = isMe
        ? Colors.black.withValues(alpha: 0.15)
        : cs.primary.withValues(alpha: 0.12);

    final textColor = isMe ? cs.onPrimary : cs.primary;

    final prefix = type == MentionType.user ? '@' : '#';
    final label = displayName.startsWith(prefix)
        ? displayName
        : '$prefix$displayName';

    final fontSize = (style.fontSize ?? 14) * 0.92;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: style.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: textColor,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
