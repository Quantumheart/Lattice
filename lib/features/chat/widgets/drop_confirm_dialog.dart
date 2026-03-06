import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

bool _isImage(String name) {
  final lower = name.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

Future<bool> confirmDroppedFiles(BuildContext context, List<DropItem> files) async {
  final previews = <_FilePreview>[];
  for (final file in files) {
    final bytes = _isImage(file.name) ? await file.readAsBytes() : null;
    previews.add(_FilePreview(name: file.name, imageBytes: bytes));
  }

  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(files.length == 1 ? 'Send file?' : 'Send ${files.length} files?'),
      content: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: previews.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _FilePreviewTile(preview: previews[i]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Send'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _FilePreview {
  const _FilePreview({required this.name, this.imageBytes});
  final String name;
  final Uint8List? imageBytes;
}

class _FilePreviewTile extends StatelessWidget {
  const _FilePreviewTile({required this.preview});

  final _FilePreview preview;

  @override
  Widget build(BuildContext context) {
    if (preview.imageBytes != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              preview.imageBytes!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(preview.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.insert_drive_file_outlined, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(preview.name, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
