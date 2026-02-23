import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:lattice/services/matrix_service.dart';
import 'package:lattice/widgets/homeserver_controller.dart';

@GenerateNiceMocks([
  MockSpec<MatrixService>(),
])
import 'homeserver_controller_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrixService;

  setUp(() {
    mockMatrixService = MockMatrixService();
  });

  HomeserverController createController() {
    return HomeserverController(matrixService: mockMatrixService);
  }

  group('HomeserverController', () {
    group('initial state', () {
      test('starts in idle state', () {
        final controller = createController();
        expect(controller.state, HomeserverState.idle);
        expect(controller.capabilities, isNull);
        expect(controller.error, isNull);
        controller.dispose();
      });
    });

    group('checkServer', () {
      test('transitions to ready when password login is supported', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.ready);
        expect(controller.capabilities!.supportsPassword, isTrue);
        expect(controller.capabilities!.supportsSso, isFalse);
        controller.dispose();
      });

      test('transitions to ready when SSO is supported', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsSso: true,
                  ssoIdentityProviders: [
                    SsoIdentityProvider(id: 'google', name: 'Google'),
                  ],
                ));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.ready);
        expect(controller.capabilities!.supportsSso, isTrue);
        expect(controller.capabilities!.ssoIdentityProviders, hasLength(1));
        controller.dispose();
      });

      test('transitions to ready when both password and SSO are supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                  supportsSso: true,
                ));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.ready);
        expect(controller.capabilities!.supportsPassword, isTrue);
        expect(controller.capabilities!.supportsSso, isTrue);
        controller.dispose();
      });

      test('transitions to error when neither password nor SSO is supported',
          () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities());

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.error);
        expect(controller.error, isNotNull);
        controller.dispose();
      });

      test('transitions to error on SocketException', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(const SocketException('Connection refused'));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.error);
        expect(controller.error, 'Could not reach server');
        controller.dispose();
      });

      test('transitions to error on TimeoutException', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(TimeoutException('Timed out'));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.error);
        expect(controller.error, 'Connection timed out');
        controller.dispose();
      });

      test('transitions to error on FormatException', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenThrow(const FormatException('Bad response'));

        final controller = createController();
        await controller.checkServer('example.com');

        expect(controller.state, HomeserverState.error);
        expect(controller.error, 'Invalid server response');
        controller.dispose();
      });

      test('discards stale server check results', () async {
        final firstCompleter = Completer<ServerAuthCapabilities>();
        var callCount = 0;

        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) {
          callCount++;
          if (callCount == 1) return firstCompleter.future;
          return Future.value(const ServerAuthCapabilities(
            supportsPassword: true,
          ));
        });

        final controller = createController();

        // Start first check (slow).
        final first = controller.checkServer('slow.org');

        // Start second check (fast) — should supersede the first.
        final second = controller.checkServer('fast.org');
        await second;

        expect(controller.state, HomeserverState.ready);
        expect(controller.capabilities!.supportsPassword, isTrue);

        // Complete the first check — it should be discarded.
        firstCompleter.complete(const ServerAuthCapabilities(
          supportsSso: true,
        ));
        await first;

        // State should still reflect the second check.
        expect(controller.capabilities!.supportsPassword, isTrue);
        expect(controller.capabilities!.supportsSso, isFalse);
        controller.dispose();
      });
    });

    group('dispose', () {
      test('does not notify after dispose', () async {
        when(mockMatrixService.getServerAuthCapabilities(any))
            .thenAnswer((_) async => const ServerAuthCapabilities(
                  supportsPassword: true,
                ));

        final controller = createController();
        controller.dispose();

        // Should not throw when the async check completes after dispose.
        await controller.checkServer('example.com');
      });
    });
  });
}
