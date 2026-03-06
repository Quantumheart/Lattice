import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

bool _isImage(String name) {
  final lower = name.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

Future<bool> confirmDroppedFiles(BuildContext context, List<DropItem> files) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(files.length == 1 ? 'Send file?' : 'Send ${files.length} files?'),
      content: SizedBox(
        width: 400,
        height: files.length == 1 ? 56 : (files.length.clamp(2, 5) * 64).toDouble(),
        child: ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _FilePreviewTile(file: files[i]),
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

class _FilePreviewTile extends StatelessWidget {
  const _FilePreviewTile({required this.file});

  final DropItem file;

  @override
  Widget build(BuildContext context) {
    final name = file.name;
    if (_isImage(name)) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return Image.memory(
                  snap.data!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.insert_drive_file_outlined, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
