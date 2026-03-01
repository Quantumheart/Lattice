import '../../services/preferences_service.dart';

// ── Density metrics ──────────────────────────────────────────

class DensityMetrics {
  const DensityMetrics({
    required this.firstMessageTopPad,
    required this.messageTopPad,
    required this.messageBottomPad,
    required this.avatarRadius,
    required this.avatarFontSize,
    required this.bubbleHorizontalPad,
    required this.bubbleVerticalPad,
    required this.bubbleRadius,
    required this.senderNameBottomPad,
    required this.senderNameFontSize,
    required this.bodyFontSize,
    required this.bodyLineHeight,
    required this.timestampTopPad,
    required this.timestampFontSize,
    required this.statusIconSize,
  });

  final double firstMessageTopPad;
  final double messageTopPad;
  final double messageBottomPad;
  final double avatarRadius;
  final double avatarFontSize;
  final double bubbleHorizontalPad;
  final double bubbleVerticalPad;
  final double bubbleRadius;
  final double senderNameBottomPad;
  final double senderNameFontSize;
  final double bodyFontSize;
  final double bodyLineHeight;
  final double timestampTopPad;
  final double timestampFontSize;
  final double statusIconSize;

  static const _compact = DensityMetrics(
    firstMessageTopPad: 6,
    messageTopPad: 1,
    messageBottomPad: 1,
    avatarRadius: 12,
    avatarFontSize: 9,
    bubbleHorizontalPad: 10,
    bubbleVerticalPad: 6,
    bubbleRadius: 16,
    senderNameBottomPad: 2,
    senderNameFontSize: 11,
    bodyFontSize: 13,
    bodyLineHeight: 1.3,
    timestampTopPad: 3,
    timestampFontSize: 9,
    statusIconSize: 12,
  );

  static const _default = DensityMetrics(
    firstMessageTopPad: 10,
    messageTopPad: 2,
    messageBottomPad: 2,
    avatarRadius: 14,
    avatarFontSize: 11,
    bubbleHorizontalPad: 14,
    bubbleVerticalPad: 9,
    bubbleRadius: 18,
    senderNameBottomPad: 3,
    senderNameFontSize: 12,
    bodyFontSize: 14,
    bodyLineHeight: 1.4,
    timestampTopPad: 4,
    timestampFontSize: 10,
    statusIconSize: 13,
  );

  static const _comfortable = DensityMetrics(
    firstMessageTopPad: 14,
    messageTopPad: 4,
    messageBottomPad: 4,
    avatarRadius: 16,
    avatarFontSize: 12,
    bubbleHorizontalPad: 16,
    bubbleVerticalPad: 12,
    bubbleRadius: 20,
    senderNameBottomPad: 4,
    senderNameFontSize: 13,
    bodyFontSize: 15,
    bodyLineHeight: 1.5,
    timestampTopPad: 5,
    timestampFontSize: 11,
    statusIconSize: 14,
  );

  static DensityMetrics of(MessageDensity density) => switch (density) {
        MessageDensity.compact => _compact,
        MessageDensity.defaultDensity => _default,
        MessageDensity.comfortable => _comfortable,
      };
}
