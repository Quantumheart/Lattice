import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<String?> confirmPastedImage(
  BuildContext context,
  Uint8List imageBytes,
  String defaultName,
) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasteConfirmDialog(
      imageBytes: imageBytes,
      defaultName: defaultName,
    ),
  );
}

class _PasteConfirmDialog extends StatefulWidget {
  const _PasteConfirmDialog({
    required this.imageBytes,
    required this.defaultName,
  });

  final Uint8List imageBytes;
  final String defaultName;

  @override
  State<_PasteConfirmDialog> createState() => _PasteConfirmDialogState();
}

class _PasteConfirmDialogState extends State<_PasteConfirmDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send pasted image?'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 300),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Filename',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            Navigator.of(context).pop(
              name.isEmpty ? widget.defaultName : name,
            );
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}
