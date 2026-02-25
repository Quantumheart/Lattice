import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/preferences_service.dart';

// ── Theme picker dialog ─────────────────────────────────────────

class ThemePickerDialog extends StatelessWidget {
  const ThemePickerDialog._();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ThemePickerDialog._(),
    );
  }

  static const _options = [
    (ThemeMode.system, 'System default'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<PreferencesService>();
    return AlertDialog(
      title: const Text('Theme'),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: RadioGroup<ThemeMode>(
        groupValue: prefs.themeMode,
        onChanged: (ThemeMode? value) {
          if (value != null) {
            prefs.setThemeMode(value);
            Navigator.pop(context);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _options.map((option) {
            final (mode, label) = option;
            return RadioListTile<ThemeMode>(
              title: Text(label),
              value: mode,
              mouseCursor: SystemMouseCursors.click,
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
