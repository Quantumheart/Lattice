import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lattice/core/utils/format_file_size.dart';
import 'package:matrix/matrix.dart';

// coverage:ignore-start

// ── File bubble (generic file attachment) ─────────────────────

class FileBubble extends StatefulWidget {
  const FileBubble({required this.event, required this.isMe, super.key});

  final Event event;
  final bool isMe;

  @override
  State<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends State<FileBubble> {
  bool _downloading = false;

  Future<void> _download() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);

    try {
      final file = await widget.event.downloadAndDecryptAttachment();
      final path = await FilePicker.platform.saveFile(
        fileName: widget.event.body,
        bytes: file.bytes,
      );

      if (path != null && file.bytes.isNotEmpty) {
        await File(path).writeAsBytes(file.bytes);
        scaffold.showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      debugPrint('[Lattice] File download failed: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Failed to save')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final foreground = widget.isMe ? cs.onPrimary : cs.onSurface;

    final fileName = widget.event.body;
    final infoMap = widget.event.content.tryGet<Map<String, Object?>>('info');
    final fileSize = infoMap?.tryGet<int>('size');

    return InkWell(
      onTap: _downloading ? null : _download,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              size: 28,
              color: foreground.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (fileSize != null)
                    Text(
                      formatFileSize(fileSize),
                      style: tt.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_downloading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground.withValues(alpha: 0.7),
                ),
              )
            else
              Icon(
                Icons.download_rounded,
                size: 22,
                color: foreground.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}
// coverage:ignore-end
