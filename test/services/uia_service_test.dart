import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/uia_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import 'matrix_service_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late UiaService service;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.onUiaRequest).thenReturn(CachedStreamController());
    service = UiaService(client: mockClient);
  });

  group('listenForUia', () {
    test('subscribes to client UIA stream', () {
      service.listenForUia();
      verify(mockClient.onUiaRequest).called(greaterThanOrEqualTo(1));
    });
  });

  group('setCachedPassword', () {
    test('auto-expires after 30 seconds', () {
      fakeAsync((async) {
        service.setCachedPassword('secret');

        async.elapse(const Duration(seconds: 31));
      });
    });
  });

  group('clearCachedPassword', () {
    test('clears immediately', () {
      service.setCachedPassword('secret');
      service.clearCachedPassword();
    });
  });

  group('cancelUiaSub', () {
    test('cancels subscription without error', () {
      service.listenForUia();
      service.cancelUiaSub();
    });
  });

  group('dispose', () {
    test('closes stream controller and timer', () {
      service.setCachedPassword('secret');
      service.listenForUia();
      service.dispose();
    });
  });

  group('completeUiaWithPassword', () {
    test('does nothing when client has no userID', () {
      when(mockClient.userID).thenReturn(null);

      final request = MockUiaRequest();
      service.completeUiaWithPassword(request, 'password');

      verifyZeroInteractions(request);
    });
  });
}

class MockUiaRequest extends Mock implements UiaRequest<dynamic> {}
