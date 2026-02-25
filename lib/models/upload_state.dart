enum UploadStatus { uploading, error }

class UploadState {
  const UploadState({
    required this.status,
    required this.fileName,
    this.error,
  });

  final UploadStatus status;
  final String fileName;
  final String? error;
}
