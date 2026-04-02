import 'package:flutter/material.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:provider/provider.dart';

class AccentColorPicker extends StatelessWidget {
  const AccentColorPicker({super.key});

  static const List<({String name, Color color})> presets = [
    (name: 'Blue', color: Color(0xFF1976D2)),
    (name: 'Teal', color: Color(0xFF009688)),
    (name: 'Green', color: Color(0xFF4CAF50)),
    (name: 'Lime', color: Color(0xFF8BC34A)),
    (name: 'Yellow', color: Color(0xFFFFC107)),
    (name: 'Amber', color: Color(0xFFFF9800)),
    (name: 'Orange', color: Color(0xFFFF5722)),
    (name: 'Red', color: Color(0xFFF44336)),
    (name: 'Pink', color: Color(0xFFE91E63)),
    (name: 'Purple', color: Color(0xFF9C27B0)),
    (name: 'Violet', color: Color(0xFF6750A4)),
    (name: 'Indigo', color: Color(0xFF3F51B5)),
    (name: 'Brown', color: Color(0xFF795548)),
    (name: 'Blue Grey', color: Color(0xFF607D8B)),
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final selected = prefs.accentColor;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ColorSwatch(
          color: null,
          selected: selected == null,
          onTap: () => prefs.setAccentColor(null),
        ),
        for (final preset in presets)
          _ColorSwatch(
            color: preset.color,
            selected: selected?.toARGB32() == preset.color.toARGB32(),
            onTap: () => prefs.setAccentColor(preset.color),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAuto = color == null;
    final displayColor = color ?? cs.primary;

    return Tooltip(
      message: isAuto ? 'Auto' : '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isAuto ? null : displayColor,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: cs.primary, width: 3)
                : Border.all(color: cs.outlineVariant),
            gradient: isAuto
                ? const SweepGradient(
                    colors: [
                      Colors.blue,
                      Colors.teal,
                      Colors.green,
                      Colors.amber,
                      Colors.red,
                      Colors.purple,
                      Colors.blue,
                    ],
                  )
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: isAuto ? Colors.white : _contrastColor(displayColor),
                )
              : null,
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
