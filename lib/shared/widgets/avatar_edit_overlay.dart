import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/shared/widgets/room_avatar.dart';

/// Wraps a [RoomAvatarWidget] with avatar editing controls.
///
/// Tapping the avatar opens the image picker to upload a new photo.
/// A small "x" badge at the top-right removes the current avatar.
/// Only shows controls if the user has permission to change the avatar.
class AvatarEditOverlay extends StatelessWidget {
  const AvatarEditOverlay({
    super.key,
    required this.room,
    this.size = 72,
  });

  final Room room;
  final double size;

  bool get _canEdit => room.canChangeStateEvent(EventTypes.RoomAvatar);

  @override
  Widget build(BuildContext context) {
    if (!_canEdit) return RoomAvatarWidget(room: room, size: size);

    final cs = Theme.of(context).colorScheme;
    final badgeSize = size * 0.3;

    final badgeOffset = badgeSize * 0.25;

    return SizedBox(
      width: size + badgeOffset,
      height: size + badgeOffset,
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _uploadAvatar(context),
                child: RoomAvatarWidget(room: room, size: size),
              ),
            ),
          ),
          if (room.avatar != null)
            Positioned(
              top: 0,
              right: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _removeAvatar(context),
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

  Future<void> _uploadAvatar(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
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
      await room.setAvatar(MatrixFile(bytes: bytes, name: picked.name));
      debugPrint('[Lattice] Room avatar uploaded: ${picked.name} (${bytes.length} bytes)');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Avatar updated')),
      );
    } catch (e) {
      debugPrint('[Lattice] Avatar upload failed: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Failed to update avatar')),
      );
    }
  }

  Future<void> _removeAvatar(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await room.setAvatar(null);
      debugPrint('[Lattice] Room avatar removed');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Avatar removed')),
      );
    } catch (e) {
      debugPrint('[Lattice] Avatar removal failed: $e');
      scaffold.showSnackBar(
        const SnackBar(content: Text('Failed to remove avatar')),
      );
    }
  }
}
