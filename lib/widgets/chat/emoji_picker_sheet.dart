import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show EmojiPicker, Config, EmojiViewConfig, CategoryViewConfig,
         SkinToneConfig, BottomActionBarConfig, SearchViewConfig,
         DefaultEmojiTextStyle;
import 'package:flutter/material.dart';

/// Shows a floating emoji picker dialog near the center of the screen.
void showEmojiPickerSheet(BuildContext context, void Function(String emoji) onSelected) {
  showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => _EmojiPickerDialog(onSelected: onSelected),
  );
}

class _EmojiPickerDialog extends StatelessWidget {
  const _EmojiPickerDialog({required this.onSelected});

  final void Function(String emoji) onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 350,
        height: 400,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.of(context).pop();
            onSelected(emoji.emoji);
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
              dialogBackgroundColor: cs.surfaceContainerHighest,
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
    );
  }
}
