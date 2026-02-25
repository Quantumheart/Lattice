import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/preferences_service.dart';

// ── Density picker dialog ───────────────────────────────────────

class DensityPickerDialog extends StatelessWidget {
  const DensityPickerDialog._();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const DensityPickerDialog._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.read<PreferencesService>();
    return AlertDialog(
      title: const Text('Message density'),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: RadioGroup<MessageDensity>(
        groupValue: prefs.messageDensity,
        onChanged: (MessageDensity? value) {
          if (value != null) {
            prefs.setMessageDensity(value);
            Navigator.pop(context);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: MessageDensity.values.map((density) {
            return RadioListTile<MessageDensity>(
              title: Text(density.label),
              value: density,
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
