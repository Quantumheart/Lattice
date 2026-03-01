import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show DefaultEmojiTextStyle, EmojiPicker, Config, EmojiViewConfig,
         CategoryViewConfig, SkinToneConfig, BottomActionBarConfig,
         SearchViewConfig;
import 'package:flutter/material.dart';

// ── Hover action bar ────────────────────────────────────────

class HoverActionBar extends StatefulWidget {
  const HoverActionBar({
    super.key,
    required this.cs,
    this.onReact,
    this.onQuickReact,
    this.onReply,
    required this.onMore,
    this.onQuickReactOpenChanged,
  });

  final ColorScheme cs;
  final VoidCallback? onReact;
  final void Function(String emoji)? onQuickReact;
  final VoidCallback? onReply;
  final void Function(Offset position) onMore;

  /// Notifies the parent when the quick-react overlay opens/closes.
  final ValueChanged<bool>? onQuickReactOpenChanged;

  @override
  State<HoverActionBar> createState() => _HoverActionBarState();
}

class _HoverActionBarState extends State<HoverActionBar> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    widget.onQuickReactOpenChanged?.call(false);
  }

  void _showQuickReactPopup() {
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    widget.onQuickReactOpenChanged?.call(true);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _QuickReactOverlay(
        link: _layerLink,
        anchorSize: box.size,
        cs: widget.cs,
        hasMore: widget.onReact != null,
        onEmojiSelected: (emoji) {
          _removeOverlay();
          widget.onQuickReact?.call(emoji);
        },
        onDismiss: _removeOverlay,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final hasReact = widget.onReact != null || widget.onQuickReact != null;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(16),
          color: widget.cs.surfaceContainerHighest,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasReact)
                _ActionIcon(
                  icon: Icons.add_reaction_outlined,
                  onTap: _showQuickReactPopup,
                  cs: widget.cs,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              if (widget.onReply != null)
                _ActionIcon(
                  icon: Icons.reply_rounded,
                  onTap: widget.onReply!,
                  cs: widget.cs,
                ),
              _ActionIcon(
                icon: Icons.more_horiz_rounded,
                onTap: () {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null || !box.hasSize) return;
                  final pos = box.localToGlobal(
                    Offset(box.size.width, box.size.height / 2),
                  );
                  widget.onMore(pos);
                },
                cs: widget.cs,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action icon ─────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.onTap,
    required this.cs,
    this.borderRadius,
  });

  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: borderRadius ?? BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ── Quick-react overlay ─────────────────────────────────────

class _QuickReactOverlay extends StatefulWidget {
  const _QuickReactOverlay({
    required this.link,
    required this.anchorSize,
    required this.cs,
    required this.hasMore,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  final LayerLink link;
  final Size anchorSize;
  final ColorScheme cs;

  /// Whether to show the "..." button (only when a full emoji picker is available).
  final bool hasMore;
  final void Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  @override
  State<_QuickReactOverlay> createState() => _QuickReactOverlayState();
}

class _QuickReactOverlayState extends State<_QuickReactOverlay> {
  bool _showPicker = false;

  static const _quickEmojis = [
    '\u{2764}\u{FE0F}', // ❤️
    '\u{1F44D}', // 👍
    '\u{1F44E}', // 👎
    '\u{1F602}', // 😂
    '\u{1F622}', // 😢
    '\u{1F62E}', // 😮
  ];

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    const gap = 4.0;

    return Stack(
      children: [
        // Dismiss scrim
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -gap),
          child: UnconstrainedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Full emoji picker (above the quick-react bar)
                if (_showPicker)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: cs.surfaceContainer,
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: 350,
                        height: 400,
                        child: EmojiPicker(
                          onEmojiSelected: (category, emoji) {
                            widget.onEmojiSelected(emoji.emoji);
                          },
                          config: Config(
                            emojiTextStyle: DefaultEmojiTextStyle,
                            emojiViewConfig: EmojiViewConfig(
                              columns: 8,
                              emojiSizeMax: 28,
                              backgroundColor: cs.surfaceContainer,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backgroundColor: cs.surfaceContainer,
                              indicatorColor: cs.primary,
                              iconColorSelected: cs.primary,
                              iconColor: cs.onSurfaceVariant,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor:
                                  cs.surfaceContainerHighest,
                              indicatorColor: cs.primary,
                            ),
                            bottomActionBarConfig: BottomActionBarConfig(
                              backgroundColor: cs.surfaceContainer,
                              buttonColor: cs.primary,
                            ),
                            searchViewConfig: SearchViewConfig(
                              backgroundColor: cs.surfaceContainer,
                              buttonIconColor: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Quick-react bar
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  color: cs.surfaceContainerHighest,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final emoji in _quickEmojis)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => widget.onEmojiSelected(emoji),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                emoji,
                                style: DefaultEmojiTextStyle.copyWith(
                                    fontSize: 22),
                              ),
                            ),
                          ),
                        if (widget.hasMore)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () =>
                                setState(() => _showPicker = !_showPicker),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 22,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
