import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/media_playback_service.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<MediaPlaybackService>()])
import 'audio_bubble_test.mocks.dart';

Widget _wrap(Event event, {bool isMe = true, MediaPlaybackService? playbackService}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<MediaPlaybackService>.value(
        value: playbackService ?? MockMediaPlaybackService(),
        child: AudioBubble(event: event, isMe: isMe),
      ),
    ),
  );
}

void main() {
  group('AudioBubble', () {
    late MockEvent mockEvent;

    setUp(() {
      mockEvent = MockEvent();
      when(mockEvent.eventId).thenReturn('event_1');
      when(mockEvent.body).thenReturn('audio.mp3');
      when(mockEvent.content).thenReturn({
        'info': {
          'duration': 5000,
          'size': 1024 * 1024,
        },
      });
      when(mockEvent.status).thenReturn(EventStatus.sent);
    });

    testWidgets('renders correctly in initial state', (tester) async {
      await tester.pumpWidget(_wrap(mockEvent));

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:05'), findsOneWidget); // info duration
      expect(find.byType(CustomPaint), findsAtLeast(1)); // waveform
    });

    testWidgets('renders file fallback when too large', (tester) async {
      when(mockEvent.content).thenReturn({
        'info': {
          'size': 200 * 1024 * 1024, // 200 MB > 100 MB limit
        },
      });

      await tester.pumpWidget(_wrap(mockEvent));

      expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
      expect(find.text('audio.mp3'), findsOneWidget);
      expect(find.text('200.0 MB'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('play button is disabled when pending send', (tester) async {
      when(mockEvent.status).thenReturn(EventStatus.sending);

      await tester.pumpWidget(_wrap(mockEvent));

      final playButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(playButton.onPressed, isNull);
    });

    testWidgets('shows loading state then error when clicking play', (tester) async {
      // Create a completer to control the download
      final completer = Completer<MatrixFile>();
      
      when(mockEvent.downloadAndDecryptAttachment(
        getThumbnail: anyNamed('getThumbnail'),
        downloadCallback: anyNamed('downloadCallback'),
        fromLocalStoreOnly: anyNamed('fromLocalStoreOnly'),
        onDownloadProgress: anyNamed('onDownloadProgress'),
      ),).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_wrap(mockEvent));
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      
      // We use pump() to trigger the async operation and the first setState
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      // Now complete with error
      completer.completeError(Exception('Download failed'));
      
      // Settle to let it handle the error and switch to error state
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget); // error state
    });

    testWidgets('handles missing info duration and size gracefully', (tester) async {
      when(mockEvent.content).thenReturn({}); // Missing 'info'
      await tester.pumpWidget(_wrap(mockEvent));

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget); // fallback duration
    });

    testWidgets('play button is disabled when status is error', (tester) async {
      when(mockEvent.status).thenReturn(EventStatus.error);

      await tester.pumpWidget(_wrap(mockEvent));

      final playButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(playButton.onPressed, isNull);
    });
  });
}
