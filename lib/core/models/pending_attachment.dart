import 'dart:typed_data';

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

class PendingAttachment {
  const PendingAttachment({
    required this.bytes,
    required this.name,
    required this.isImage,
  });

  factory PendingAttachment.fromBytes({
    required Uint8List bytes,
    required String name,
  }) {
    return PendingAttachment(
      bytes: bytes,
      name: name,
      isImage: isImageFile(name),
    );
  }

  final Uint8List bytes;
  final String name;
  final bool isImage;

  static bool isImageFile(String name) {
    final lower = name.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }
}
