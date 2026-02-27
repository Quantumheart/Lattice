import 'package:emoji_picker_flutter/emoji_picker_flutter.dart'
    show EmojiPicker, Config, EmojiViewConfig, CategoryViewConfig,
         SkinToneConfig, BottomActionBarConfig, SearchViewConfig,
         DefaultEmojiTextStyle;
import 'package:flutter/material.dart';

/// Shows a modal bottom sheet with an emoji picker grid.
void showEmojiPickerSheet(BuildContext context, void Function(String emoji) onSelected) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return SizedBox(
        height: 300,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.of(context).pop();
            onSelected(emoji.emoji);
          },
          config: Config(
            emojiTextStyle: DefaultEmojiTextStyle,
            emojiViewConfig: EmojiViewConfig(
              columns: 7,
              emojiSizeMax: 28,
              backgroundColor: cs.surface,
            ),
            categoryViewConfig: CategoryViewConfig(
              indicatorColor: cs.primary,
              iconColorSelected: cs.primary,
            ),
            skinToneConfig: SkinToneConfig(
              dialogBackgroundColor: cs.surfaceContainerHighest,
              indicatorColor: cs.primary,
            ),
            bottomActionBarConfig: BottomActionBarConfig(
              backgroundColor: cs.surface,
              buttonColor: cs.primary,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: cs.surface,
            ),
          ),
        ),
      );
    },
  );
}
