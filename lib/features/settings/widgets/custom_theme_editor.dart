import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/core/theme/custom_theme.dart';
import 'package:provider/provider.dart';

class CustomThemeEditor extends StatelessWidget {
  const CustomThemeEditor({super.key});

  static const _slots = [
    ('background', 'Background'),
    ('foreground', 'Foreground'),
    ('primary', 'Primary'),
    ('secondary', 'Secondary'),
    ('muted', 'Muted'),
    ('border', 'Border'),
    ('highlight', 'Highlight'),
  ];

  Color _getSlotColor(CustomTheme theme, String slot) => switch (slot) {
    'background' => theme.background,
    'foreground' => theme.foreground,
    'primary' => theme.primary,
    'secondary' => theme.secondary,
    'muted' => theme.muted,
    'border' => theme.border,
    'highlight' => theme.highlight,
    _ => Colors.transparent,
  };

  CustomTheme _setSlotColor(CustomTheme theme, String slot, Color color) =>
      switch (slot) {
        'background' => theme.copyWith(background: color),
        'foreground' => theme.copyWith(foreground: color),
        'primary' => theme.copyWith(primary: color),
        'secondary' => theme.copyWith(secondary: color),
        'muted' => theme.copyWith(muted: color),
        'border' => theme.copyWith(border: color),
        'highlight' => theme.copyWith(highlight: color),
        _ => theme,
      };

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesService>();
    final theme = prefs.customTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Custom Theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode, size: 16),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode, size: 16),
                ),
              ],
              selected: {prefs.customThemeMode},
              onSelectionChanged: (s) => prefs.setCustomThemeMode(s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            const columns = 5;
            final slotWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (slot, label) in _slots)
                  SizedBox(
                    width: slotWidth,
                    child: _ColorSlot(
                      label: label,
                      color: _getSlotColor(theme, slot),
                      borderColor: cs.outlineVariant,
                      onColorChanged: (color) {
                        final updated = _setSlotColor(theme, slot, color);
                        unawaited(prefs.setCustomTheme(updated));
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: () => prefs.setCustomTheme(CustomTheme.defaults),
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onColorChanged,
  });

  final String label;
  final Color color;
  final Color borderColor;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _showColorPicker(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => _HexColorPickerDialog(initial: color),
    );
    if (result != null) onColorChanged(result);
  }
}

class _HexColorPickerDialog extends StatefulWidget {
  const _HexColorPickerDialog({required this.initial});
  final Color initial;

  @override
  State<_HexColorPickerDialog> createState() => _HexColorPickerDialogState();
}

class _HexColorPickerDialogState extends State<_HexColorPickerDialog> {
  late TextEditingController _controller;
  late Color _preview;
  bool _valid = true;

  @override
  void initState() {
    super.initState();
    final hex = widget.initial.toARGB32().toRadixString(16).substring(2).toUpperCase();
    _controller = TextEditingController(text: hex);
    _preview = widget.initial;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final parsed = int.tryParse('FF$cleaned', radix: 16);
      if (parsed != null) {
        setState(() {
          _preview = Color(parsed);
          _valid = true;
        });
        return;
      }
    }
    setState(() => _valid = cleaned.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _preview,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              prefixText: '#',
              hintText: 'RRGGBB',
              errorText: _valid ? null : 'Invalid hex color',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(6),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.pop(context, _preview) : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
