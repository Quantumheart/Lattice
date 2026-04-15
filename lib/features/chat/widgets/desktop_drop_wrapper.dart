import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/features/chat/widgets/drop_zone_overlay.dart';

class DesktopDropWrapper extends StatefulWidget {
  const DesktopDropWrapper({
    required this.child,
    required this.onFileDropped,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final void Function(PendingAttachment attachment) onFileDropped;
  final bool enabled;

  @override
  State<DesktopDropWrapper> createState() => _DesktopDropWrapperState();
}

class _DesktopDropWrapperState extends State<DesktopDropWrapper> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        final files = details.files;
        if (files.isEmpty || !mounted) return;
        for (final file in files) {
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          widget.onFileDropped(
            PendingAttachment.fromBytes(bytes: bytes, name: file.name),
          );
        }
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isDragging ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: DropZoneOverlay(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
