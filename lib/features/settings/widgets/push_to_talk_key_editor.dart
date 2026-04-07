import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PushToTalkKeyEditor extends StatelessWidget {
  const PushToTalkKeyEditor({
    required this.keyId,
    required this.onKeyChanged,
    super.key,
  });

  final int keyId;
  final ValueChanged<int> onKeyChanged;

  String _keyLabel() {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    return key?.keyLabel ?? 'Unknown';
  }

  Future<void> _showCaptureDialog(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => _KeyCaptureDialog(currentKeyId: keyId),
    );
    if (result != null) {
      onKeyChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const SizedBox(width: 24),
      title: const Text('Key binding'),
      subtitle: Text(_keyLabel()),
      trailing: FilledButton.tonal(
        onPressed: () => _showCaptureDialog(context),
        child: const Text('Edit'),
      ),
    );
  }
}

// ── Key Capture Dialog ──────────────────────────────────────────

class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({required this.currentKeyId});

  final int currentKeyId;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }

    Navigator.pop(context, event.logicalKey.keyId);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AlertDialog(
        title: const Text('Set push-to-talk key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_rounded, size: 48, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Press a key…',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Press Escape to cancel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
