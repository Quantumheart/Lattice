import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/services/call_service.dart';
import 'package:lattice/core/services/preferences_service.dart';
import 'package:lattice/features/calling/services/push_to_talk_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_to_talk_service_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
])
void main() {
  late MockClient mockClient;
  late CallService callService;
  late PreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);

    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:matrix.org');
    when(mockClient.homeserver).thenReturn(Uri.parse('https://matrix.org'));
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync)
        .thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.encryption).thenReturn(null);
    when(mockClient.encryptionEnabled).thenReturn(false);
    when(mockClient.onLoginStateChanged)
        .thenReturn(CachedStreamController<LoginState>());
    when(mockClient.onUiaRequest)
        .thenReturn(CachedStreamController<UiaRequest<dynamic>>());

    callService = CallService(client: mockClient);
  });

  test('creates without error when PTT disabled', () {
    final service = PushToTalkService(
      callService: callService,
      prefs: prefs,
    );
    expect(service.isKeyHeld, isFalse);
    service.dispose();
  });

  test('does not crash when disposed', () {
    final service = PushToTalkService(
      callService: callService,
      prefs: prefs,
    );
    service.dispose();
  });
}
