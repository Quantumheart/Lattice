import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lattice/services/preferences_service.dart';
import 'package:lattice/utils/notification_filter.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<Client>()])
import 'notification_filter_test.mocks.dart';

void main() {
  late PreferencesService prefs;
  late MockRoom mockRoom;
  late MockClient mockClient;

  const ownUserId = '@me:example.com';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);
    mockClient = MockClient();
    mockRoom = MockRoom();
    when(mockRoom.notificationCount).thenReturn(5);
    when(mockRoom.highlightCount).thenReturn(0);
    when(mockRoom.lastEvent).thenReturn(null);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn(ownUserId);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(ownUserId))
        .thenReturn(User(ownUserId, room: mockRoom, displayName: 'Me'));
  });

  // ── effectiveUnreadCount ─────────────────────────────────────

  group('effectiveUnreadCount', () {
    test('returns notificationCount when level is all', () {
      expect(effectiveUnreadCount(mockRoom, prefs), 5);
    });

    test('returns 0 when level is off', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(effectiveUnreadCount(mockRoom, prefs), 0);
    });

    test('returns highlightCount when mentionsOnly with highlights', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      when(mockRoom.highlightCount).thenReturn(3);
      expect(effectiveUnreadCount(mockRoom, prefs), 3);
    });

    test('returns 1 when mentionsOnly with keyword match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await prefs.addNotificationKeyword('hello');
      final event = _FakeEvent(fakeBody: 'say hello everyone');
      when(mockRoom.lastEvent).thenReturn(event);
      expect(effectiveUnreadCount(mockRoom, prefs), 1);
    });

    test('returns 0 when mentionsOnly with no match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      final event = _FakeEvent(fakeBody: 'nothing relevant');
      when(mockRoom.lastEvent).thenReturn(event);
      expect(effectiveUnreadCount(mockRoom, prefs), 0);
    });

    test('returns 0 when mentionsOnly with null lastEvent', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(effectiveUnreadCount(mockRoom, prefs), 0);
    });
  });

  // ── shouldNotifyForEvent ─────────────────────────────────────

  group('shouldNotifyForEvent', () {
    test('returns false for own messages', () {
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@me:example.com',
          ownUserId: '@me:example.com',
          room: mockRoom,
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('returns true for all level', () {
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          room: mockRoom,
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('returns false for off level', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          room: mockRoom,
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('mentionsOnly returns true when body contains user ID', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hey @me:example.com check this',
          senderId: '@other:example.com',
          ownUserId: ownUserId,
          room: mockRoom,
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns true when body contains display name',
        () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hey Me, are you there?',
          senderId: '@other:example.com',
          ownUserId: ownUserId,
          room: mockRoom,
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns true on keyword match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await prefs.addNotificationKeyword('urgent');
      expect(
        shouldNotifyForEvent(
          eventBody: 'This is URGENT please respond',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          room: mockRoom,
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns false with no match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'just a normal message',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          room: mockRoom,
          prefs: prefs,
        ),
        isFalse,
      );
    });
  });
}

/// Minimal fake Event for testing body access on lastEvent.
class _FakeEvent extends Fake implements Event {
  _FakeEvent({required this.fakeBody});
  final String fakeBody;

  @override
  String get body => fakeBody;
}
