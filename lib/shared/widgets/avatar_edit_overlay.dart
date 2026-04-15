import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';

/// Wraps a [RoomAvatarWidget] with avatar editing controls.
///
/// Tapping the avatar opens the image picker to upload a new photo.
/// A small "x" badge at the top-right removes the current avatar.
/// Only shows controls if the user has permission to change the avatar.
class AvatarEditOverlay extends StatefulWidget {
  const AvatarEditOverlay({
    required this.room, super.key,
    this.size = 72,
  });

  final Room room;
  final double size;

  @override
  State<AvatarEditOverlay> createState() => _AvatarEditOverlayState();
}

class _AvatarEditOverlayState extends State<AvatarEditOverlay> {
  bool _busy = false;

  bool get _canEdit => widget.room.canChangeStateEvent(EventTypes.RoomAvatar);

  @override
  Widget build(BuildContext context) {
    if (!_canEdit) return RoomAvatarWidget(room: widget.room, size: widget.size);

    final cs = Theme.of(context).colorScheme;
    final badgeSize = widget.size * 0.3;
    final badgeOffset = badgeSize * 0.25;

    // Pad all sides equally so the avatar stays centered when the badge
    // protrudes beyond the avatar bounds.
    return Padding(
      padding: EdgeInsets.all(badgeOffset),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MouseRegion(
            cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _busy ? null : _uploadAvatar,
              child: RoomAvatarWidget(room: widget.room, size: widget.size),
            ),
          ),
          if (widget.room.avatar != null)
            Positioned(
              top: -badgeOffset,
              right: -badgeOffset,
              child: MouseRegion(
                cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _busy ? null : _removeAvatar,
                  child: Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: badgeSize * 0.55,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _uploadAvatar() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      await widget.room.setAvatar(MatrixFile(bytes: bytes, name: picked.name));
      debugPrint('[Kohera] Room avatar uploaded: ${picked.name} (${bytes.length} bytes)');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Avatar updated')),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Avatar upload failed: $e');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to update avatar')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.room.setAvatar(null);
      debugPrint('[Kohera] Room avatar removed');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Avatar removed')),
        );
      }
    } catch (e) {
      debugPrint('[Kohera] Avatar removal failed: $e');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to remove avatar')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
