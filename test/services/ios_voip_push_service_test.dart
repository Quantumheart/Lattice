import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/app_config.dart';
import 'package:kohera/core/services/call_service.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/services/ios_voip_push_service.dart';
import 'package:kohera/features/notifications/services/notification_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';


@GenerateNiceMocks([
  MockSpec<MatrixService>(),
  MockSpec<Client>(),
  MockSpec<CallService>(),
  MockSpec<NotificationService>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])
import 'ios_voip_push_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMatrixService mockMatrix;
  late MockClient mockClient;
  late MockCallService mockCallService;
  late MockNotificationService mockNotification;
  late PreferencesService prefs;
  late IosVoipPushService service;

  const gatewayUrl = 'https://push.example.com/_matrix/push/v1/notify';
  const voipToken = 'aabbccdd11223344';

  setUp(() async {
    SharedPreferences.setMockInitialValues({'apns_push_enabled': true});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    AppConfig.setInstance(
      AppConfig.testInstance(apnsPushGatewayUrl: gatewayUrl),
    );

    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    mockCallService = MockCallService();
    mockNotification = MockNotificationService();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.userID).thenReturn('@alice:example.com');
    when(mockClient.deviceID).thenReturn('DEV1');
    when(mockClient.deviceName).thenReturn('AlicePhone');

    service = IosVoipPushService(
      matrixService: mockMatrix,
      preferencesService: prefs,
      notificationService: mockNotification,
      callService: mockCallService,
      platformCheck: () => true,
    );
  });

  tearDown(() {
    service.dispose();
    AppConfig.reset();
  });

  // ── register ────────────────────────────────────────────────

  group('register', () {
    late List<String> nativeInvocations;

    setUp(() {
      nativeInvocations = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosVoipMethodChannel, (call) async {
        nativeInvocations.add(call.method);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosVoipMethodChannel, null);
    });

    test('invokes requestVoipToken on native channel', () async {
      await service.register();
      expect(nativeInvocations, ['requestVoipToken']);
    });

    test('is a no-op when apnsPushEnabled is false', () async {
      SharedPreferences.setMockInitialValues({'apns_push_enabled': false});
      final sp = await SharedPreferences.getInstance();

      final noopService = IosVoipPushService(
        matrixService: mockMatrix,
        preferencesService: PreferencesService(prefs: sp),
        notificationService: mockNotification,
        callService: mockCallService,
        platformCheck: () => true,
      );

      await noopService.register();
      expect(nativeInvocations, isEmpty);
      noopService.dispose();
    });

    test('is a no-op when apnsPushGatewayUrl is null', () async {
      AppConfig.setInstance(AppConfig.testInstance());

      await service.register();
      expect(nativeInvocations, isEmpty);
    });
  });

  // ── onVoipToken ─────────────────────────────────────────────

  group('onVoipToken', () {
    test('posts a Pusher with correct fields', () async {
      when(mockClient.postPusher(any, append: anyNamed('append')))
          .thenAnswer((_) async {});

      await service.onVoipToken(voipToken);

      final captured = verify(
        mockClient.postPusher(captureAny, append: captureAnyNamed('append')),
      ).captured;
      final pusher = captured[0] as Pusher;
      final append = captured[1] as bool;

      expect(pusher.appId, NotificationChannel.voipAppId);
      expect(pusher.pushkey, voipToken);
      expect(pusher.appDisplayName, NotificationChannel.appName);
      expect(pusher.kind, 'http');
      expect(pusher.lang, 'en');
      expect(pusher.data.format, isNull);
      expect(pusher.data.url.toString(), gatewayUrl);
      expect(pusher.profileTag, 'DEV1');
      expect(append, isTrue);
    });

    test('re-registers pusher on token refresh', () async {
      when(mockClient.postPusher(any, append: anyNamed('append')))
          .thenAnswer((_) async {});

      await service.onVoipToken('first_token');
      await service.onVoipToken('second_token');

      final calls = verify(
        mockClient.postPusher(captureAny, append: anyNamed('append')),
      ).captured;
      expect(calls, hasLength(2));
      expect((calls[1] as Pusher).pushkey, 'second_token');
    });
  });

  // ── unregister ──────────────────────────────────────────────

  group('unregister', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosVoipMethodChannel, (_) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosVoipMethodChannel, null);
    });

    test('calls deletePusher with correct PusherId', () async {
      when(mockClient.postPusher(any, append: anyNamed('append')))
          .thenAnswer((_) async {});
      when(mockClient.deletePusher(any)).thenAnswer((_) async {});

      await service.onVoipToken(voipToken);
      await service.unregister();

      final captured =
          verify(mockClient.deletePusher(captureAny)).captured.single
              as PusherId;
      expect(captured.appId, NotificationChannel.voipAppId);
      expect(captured.pushkey, voipToken);
    });
  });

  // ── onVoipTokenInvalidated ──────────────────────────────────

  group('onVoipTokenInvalidated', () {
    test('deletes prior pusher', () async {
      when(mockClient.postPusher(any, append: anyNamed('append')))
          .thenAnswer((_) async {});
      when(mockClient.deletePusher(any)).thenAnswer((_) async {});

      await service.onVoipToken(voipToken);
      await service.onVoipTokenInvalidated();

      final captured =
          verify(mockClient.deletePusher(captureAny)).captured.single
              as PusherId;
      expect(captured.appId, NotificationChannel.voipAppId);
      expect(captured.pushkey, voipToken);
    });
  });

  // ── onVoipMessage ───────────────────────────────────────────

  Map<String, dynamic> validPayload({
    String roomId = '!room:example.com',
    String callId = 'call_42',
    String sender = 'Bob',
    bool isVideo = true,
    String? nativeCallId = 'native-uuid-1',
    bool callKitAlreadyShown = true,
  }) =>
      {
        'notification': {
          'event_type': 'org.matrix.msc3401.call.member',
          'room_id': roomId,
          'call_id': callId,
          'sender_display_name': sender,
          'is_video': isVideo,
        },
        if (nativeCallId != null) 'nativeCallId': nativeCallId,
        'callKitAlreadyShown': callKitAlreadyShown,
      };

  group('onVoipMessage', () {
    test('calls attachPrePresentedCallKit + handlePushCallInvite', () async {
      when(mockClient.oneShotSync(timeout: anyNamed('timeout')))
          .thenAnswer((_) async {});
      when(mockClient.getRoomById(any)).thenReturn(null);

      await service.onVoipMessage(validPayload());

      verify(
        mockCallService.attachPrePresentedCallKit(
          nativeCallId: 'native-uuid-1',
        ),
      ).called(1);

      verify(
        mockCallService.handlePushCallInvite(
          roomId: '!room:example.com',
          callId: 'call_42',
          callerName: 'Bob',
          isVideo: true,
          callKitAlreadyShown: true,
        ),
      ).called(1);
    });

    test('callKitAlreadyShown defaults to false when absent', () async {
      when(mockClient.oneShotSync(timeout: anyNamed('timeout')))
          .thenAnswer((_) async {});
      when(mockClient.getRoomById(any)).thenReturn(null);

      await service.onVoipMessage({
        'notification': {
          'event_type': 'org.matrix.msc3401.call.member',
          'room_id': '!room:example.com',
          'call_id': 'call_42',
          'sender_display_name': 'Bob',
          'is_video': false,
        },
        'nativeCallId': 'native-uuid-1',
      });

      verify(
        mockCallService.handlePushCallInvite(
          roomId: '!room:example.com',
          callId: 'call_42',
          callerName: 'Bob',
          isVideo: false,
          // ignore: avoid_redundant_argument_values, explicit false is the assertion
          callKitAlreadyShown: false,
        ),
      ).called(1);
    });

    test('rejects payload missing event_type', () async {
      await service.onVoipMessage({
        'notification': {
          'room_id': '!room:example.com',
          'call_id': 'call_42',
        },
      });

      verifyNever(
        mockCallService.handlePushCallInvite(
          roomId: anyNamed('roomId'),
          callId: anyNamed('callId'),
          callerName: anyNamed('callerName'),
          isVideo: anyNamed('isVideo'),
          callKitAlreadyShown: anyNamed('callKitAlreadyShown'),
        ),
      );
    });

    test('rejects payload with wrong event_type', () async {
      await service.onVoipMessage({
        'notification': {
          'event_type': 'm.call.invite',
          'room_id': '!room:example.com',
          'call_id': 'call_42',
        },
      });

      verifyNever(
        mockCallService.handlePushCallInvite(
          roomId: anyNamed('roomId'),
          callId: anyNamed('callId'),
          callerName: anyNamed('callerName'),
          isVideo: anyNamed('isVideo'),
          callKitAlreadyShown: anyNamed('callKitAlreadyShown'),
        ),
      );
    });

    test('rejects payload missing call_id', () async {
      await service.onVoipMessage({
        'notification': {
          'event_type': 'org.matrix.msc3401.call.member',
          'room_id': '!room:example.com',
        },
      });

      verifyNever(
        mockCallService.handlePushCallInvite(
          roomId: anyNamed('roomId'),
          callId: anyNamed('callId'),
          callerName: anyNamed('callerName'),
          isVideo: anyNamed('isVideo'),
          callKitAlreadyShown: anyNamed('callKitAlreadyShown'),
        ),
      );
    });

    test(
        'ends CallKit when post-sync shows caller has no remote membership',
        () async {
      when(mockClient.oneShotSync(timeout: anyNamed('timeout')))
          .thenAnswer((_) async {});

      final mockRoom = MockRoom();
      when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
      when(mockClient.userID).thenReturn('@alice:example.com');
      when(mockRoom.states).thenReturn({});
      when(mockCallService.callState)
          .thenReturn(KoheraCallState.ringingIncoming);

      await service.onVoipMessage(validPayload());

      verify(mockCallService.endCallFromPushKit()).called(1);
    });

    test('does NOT end CallKit when call state is not ringingIncoming',
        () async {
      when(mockClient.oneShotSync(timeout: anyNamed('timeout')))
          .thenAnswer((_) async {});

      when(mockCallService.callState).thenReturn(KoheraCallState.connected);

      await service.onVoipMessage(validPayload());

      verifyNever(mockCallService.endCallFromPushKit());
    });
  });
}
