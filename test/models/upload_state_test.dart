import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/core/models/upload_state.dart';

void main() {
  group('UploadState', () {
    test('creates uploading state', () {
      const state = UploadState(status: UploadStatus.uploading, fileName: 'photo.png');
      expect(state.status, UploadStatus.uploading);
      expect(state.fileName, 'photo.png');
      expect(state.error, isNull);
    });

    test('creates error state with message', () {
      const state = UploadState(
        status: UploadStatus.error,
        fileName: 'doc.pdf',
        error: 'Too large',
      );
      expect(state.status, UploadStatus.error);
      expect(state.fileName, 'doc.pdf');
      expect(state.error, 'Too large');
    });
  });

  group('UploadStatus', () {
    test('has expected values', () {
      expect(UploadStatus.values, containsAll([UploadStatus.uploading, UploadStatus.error]));
      expect(UploadStatus.values.length, 2);
    });
  });
}
