import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<MediaPlaybackService>(), MockSpec<Room>()])
import 'video_bubble_test.mocks.dart';

Widget _wrap(Event event, {bool isMe = true, MediaPlaybackService? playbackService}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<MediaPlaybackService>.value(
        value: playbackService ?? MockMediaPlaybackService(),
        child: VideoBubble(event: event, isMe: isMe),
      ),
    ),
  );
}

class FakeMatrixClient extends Fake implements Client {
  @override
  Uri get homeserver => Uri.parse('https://example.com');
}

void main() {
  group('VideoBubble', () {
    late MockEvent mockEvent;
    late MockRoom mockRoom;

    setUp(() {
      mockEvent = MockEvent();
      mockRoom = MockRoom();
      when(mockEvent.eventId).thenReturn('event_1');
      when(mockEvent.body).thenReturn('video.mp4');
      when(mockEvent.content).thenReturn({
        'info': {
          'duration': 10000,
          'size': 5 * 1024 * 1024,
        },
      });
      when(mockEvent.status).thenReturn(EventStatus.sent);
      when(mockEvent.isAttachmentEncrypted).thenReturn(false);
      when(mockEvent.room).thenReturn(mockRoom);
      
      // Mock room to avoid issues
      when(mockRoom.client).thenReturn(FakeMatrixClient());
      
      // Default thumbnail behavior: return a URI
      when(mockEvent.getAttachmentUri(
        getThumbnail: true,
        width: anyNamed('width'),
        height: anyNamed('height'),
      ),).thenAnswer((_) async => Uri.parse('https://example.com/thumb.jpg'));
    });

    testWidgets('renders thumbnail correctly (unencrypted)', (tester) async {
      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump(); // allow thumbnail load to complete

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);
    });

    testWidgets('renders thumbnail correctly (encrypted)', (tester) async {
      when(mockEvent.isAttachmentEncrypted).thenReturn(true);
      when(mockEvent.downloadAndDecryptAttachment(getThumbnail: true))
          .thenAnswer((_) async => MatrixFile(bytes: Uint8List.fromList([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 
            0x42, 0x60, 0x82,
          ]), name: 'thumb.png',),);

      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump(); // allow thumbnail load to complete

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('renders fallback when too large', (tester) async {
      when(mockEvent.content).thenReturn({
        'info': {
          'size': 200 * 1024 * 1024,
        },
      });

      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump();

      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.text('video.mp4'), findsOneWidget);
      expect(find.text('200.0 MB'), findsOneWidget);
    });

    testWidgets('shows loading video state when clicking play', (tester) async {
      final completer = Completer<MatrixFile>();
      when(mockEvent.downloadAndDecryptAttachment(
        getThumbnail: anyNamed('getThumbnail'),
        downloadCallback: anyNamed('downloadCallback'),
        fromLocalStoreOnly: anyNamed('fromLocalStoreOnly'),
        onDownloadProgress: anyNamed('onDownloadProgress'),
      ),).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump(); // finish thumb load
      
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump(); // trigger loading video state
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      completer.completeError(Exception('Playback failed'));
      await tester.pumpAndSettle();
      
      // Should show error state
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('handles missing info duration gracefully', (tester) async {
      when(mockEvent.content).thenReturn({});
      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.textContaining('00:'), findsNothing);
    });

    testWidgets('handles thumbnail load failure', (tester) async {
      when(mockEvent.getAttachmentUri(
        getThumbnail: true,
        width: anyNamed('width'),
        height: anyNamed('height'),
      ),).thenThrow(Exception('Thumbnail load failed'));

      await tester.pumpWidget(_wrap(mockEvent));
      await tester.pump();

      // Placeholder for thumbnail (Container with icon)
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
