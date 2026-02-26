import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:matrix/matrix.dart';

import 'package:lattice/services/typing_controller.dart';

@GenerateNiceMocks([MockSpec<Room>()])
import 'typing_controller_test.mocks.dart';

void main() {
  late MockRoom mockRoom;

  setUp(() {
    mockRoom = MockRoom();
    when(mockRoom.setTyping(any, timeout: anyNamed('timeout')))
        .thenAnswer((_) async {});
  });

  group('TypingController', () {
    test('onTextChanged sends typing true', () {
      final ctrl = TypingController(room: mockRoom);
      ctrl.onTextChanged('hello');

      verify(mockRoom.setTyping(true, timeout: 30000)).called(1);

      ctrl.dispose();
    });

    test('rapid calls within 4s do not re-send', () {
      fakeAsync((async) {
        final ctrl = TypingController(room: mockRoom);
        ctrl.onTextChanged('h');
        ctrl.onTextChanged('he');
        ctrl.onTextChanged('hel');

        verify(mockRoom.setTyping(true, timeout: 30000)).called(1);

        ctrl.dispose();
      });
    });

    test('re-sends after 4s+ elapsed', () {
      fakeAsync((async) {
        final ctrl = TypingController(room: mockRoom);
        ctrl.onTextChanged('h');

        async.elapse(const Duration(seconds: 5));

        ctrl.onTextChanged('he');

        verify(mockRoom.setTyping(true, timeout: 30000)).called(2);

        ctrl.dispose();
      });
    });

    test('stop sends false', () {
      final ctrl = TypingController(room: mockRoom);
      ctrl.onTextChanged('hello');

      ctrl.stop();

      verify(mockRoom.setTyping(false)).called(1);

      ctrl.dispose();
    });

    test('stop is idempotent', () {
      final ctrl = TypingController(room: mockRoom);
      ctrl.onTextChanged('hello');

      ctrl.stop();
      ctrl.stop();

      verify(mockRoom.setTyping(false)).called(1);

      ctrl.dispose();
    });

    test('30s inactivity auto-stops', () {
      fakeAsync((async) {
        final ctrl = TypingController(room: mockRoom);
        ctrl.onTextChanged('hello');

        async.elapse(const Duration(seconds: 30));

        verify(mockRoom.setTyping(false)).called(1);

        ctrl.dispose();
      });
    });

    test('empty text triggers stop', () {
      final ctrl = TypingController(room: mockRoom);
      ctrl.onTextChanged('hello');

      ctrl.onTextChanged('');

      verify(mockRoom.setTyping(false)).called(1);

      ctrl.dispose();
    });

    test('dispose calls stop', () {
      final ctrl = TypingController(room: mockRoom);
      ctrl.onTextChanged('hello');

      ctrl.dispose();

      verify(mockRoom.setTyping(false)).called(1);
    });
  });
}
