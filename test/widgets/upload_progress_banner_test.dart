import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/models/upload_state.dart';
import 'package:lattice/widgets/chat/upload_progress_banner.dart';

void main() {
  Widget buildBanner({
    required UploadState state,
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: UploadProgressBanner(
          state: state,
          onCancel: onCancel ?? () {},
        ),
      ),
    );
  }

  group('UploadProgressBanner', () {
    testWidgets('shows uploading state with spinner and filename',
        (tester) async {
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.uploading,
          fileName: 'photo.jpg',
        ),
      ));

      expect(find.text('Uploading…'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('shows error state with error icon', (tester) async {
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.error,
          fileName: 'document.pdf',
          error: 'Network error',
        ),
      ));

      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('cancel button fires callback', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(buildBanner(
        state: const UploadState(
          status: UploadStatus.uploading,
          fileName: 'file.txt',
        ),
        onCancel: () => cancelled = true,
      ));

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cancelled, isTrue);
    });
  });
}
