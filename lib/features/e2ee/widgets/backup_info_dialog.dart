import 'package:flutter/material.dart';

// ── Backup info dialog ──────────────────────────────────────────

class BackupInfoDialog extends StatelessWidget {
  const BackupInfoDialog._({required this.onDisableBackup});

  final VoidCallback onDisableBackup;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onDisableBackup,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BackupInfoDialog._(onDisableBackup: onDisableBackup),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Chat backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: cs.primary,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your keys are backed up. Your encrypted messages are '
            'secure and accessible from any device.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onDisableBackup();
          },
          child: Text(
            'Disable backup',
            style: TextStyle(color: cs.error),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
