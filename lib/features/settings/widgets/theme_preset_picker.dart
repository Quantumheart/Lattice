import 'package:flutter/material.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/theme/theme_presets.dart';
import 'package:provider/provider.dart';

class ThemePresetPicker extends StatelessWidget {
  const ThemePresetPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final selected = prefs.themePreset;

    final chips = [
      _PresetChip(
        label: 'System',
        color: Theme.of(context).colorScheme.primary,
        selected: selected == null,
        onTap: () => prefs.setThemePreset(null),
      ),
      for (final preset in themePresetList)
        _PresetChip(
          label: preset.name,
          color: preset.seedColor,
          selected: selected == preset.id,
          onTap: () => prefs.setThemePreset(preset.id),
        ),
      _PresetChip(
        label: 'Custom',
        color: Theme.of(context).colorScheme.tertiary,
        selected: selected == 'custom',
        onTap: () => prefs.setThemePreset('custom'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const columns = 6;
        final chipWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final chip in chips)
              SizedBox(width: chipWidth, child: chip),
          ],
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? _contrastColor(color) : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  static Color _contrastColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
