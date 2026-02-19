import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:lattice/widgets/key_verification_dialog.dart';

/// A fake [KeyVerification] for testing. We cannot use Mockito because
/// [onUpdate] and [state] are plain fields, not methods.
class FakeKeyVerification extends Fake implements KeyVerification {
  @override
  void Function()? onUpdate;

  @override
  KeyVerificationState state;

  @override
  String? canceledReason;

  @override
  bool canceled;

  List<KeyVerificationEmoji> _sasEmojis = [];

  @override
  List<KeyVerificationEmoji> get sasEmojis => _sasEmojis;

  @override
  List<String> possibleMethods = [];

  bool cancelCalled = false;
  bool acceptVerificationCalled = false;
  bool acceptSasCalled = false;
  bool rejectSasCalled = false;
  String? continueVerificationMethod;

  FakeKeyVerification({
    this.state = KeyVerificationState.waitingAccept,
    this.canceledReason,
    this.canceled = false,
  });

  void setSasEmojis(List<KeyVerificationEmoji> emojis) {
    _sasEmojis = emojis;
  }

  void simulateStateChange(KeyVerificationState newState) {
    state = newState;
    onUpdate?.call();
  }

  @override
  Future<void> cancel([String? code, bool quiet = false]) async {
    cancelCalled = true;
    canceled = true;
    state = KeyVerificationState.error;
  }

  @override
  Future<void> acceptVerification() async {
    acceptVerificationCalled = true;
  }

  @override
  Future<void> acceptSas() async {
    acceptSasCalled = true;
  }

  @override
  Future<void> rejectSas() async {
    rejectSasCalled = true;
  }

  @override
  Future<void> acceptQRScanConfirmation() async {}

  @override
  Future<void> continueVerification(String type,
      {Uint8List? qrDataRawBytes}) async {
    continueVerificationMethod = type;
  }

  @override
  Future<void> start() async {}

  @override
  bool get isDone =>
      canceled ||
      {KeyVerificationState.error, KeyVerificationState.done}.contains(state);
}

void main() {
  Widget buildTestApp({required FakeKeyVerification verification}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      KeyVerificationDialog(verification: verification),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester,
      {required FakeKeyVerification verification}) async {
    await tester.pumpWidget(buildTestApp(verification: verification));
    await tester.tap(find.text('Open'));
    // Use pump() not pumpAndSettle() because CircularProgressIndicator
    // animates indefinitely in spinner states.
    await tester.pump();
  }

  group('KeyVerificationDialog', () {
    testWidgets('shows spinner in waitingAccept state', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.waitingAccept,
      );
      await openDialog(tester, verification: verification);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Waiting for the other device to accept...'),
          findsOneWidget);
    });

    testWidgets('renders SAS emoji with Semantics labels', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
      );
      // KeyVerificationEmoji takes a number index (0-63)
      verification.setSasEmojis([
        KeyVerificationEmoji(0), // Dog
        KeyVerificationEmoji(1), // Cat
      ]);

      await openDialog(tester, verification: verification);

      // Verify Semantics widgets are present with labels
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      final labels = semantics
          .map((s) => s.properties.label)
          .where((l) => l != null && l.isNotEmpty)
          .toList();
      expect(labels, contains('Dog'));
      expect(labels, contains('Cat'));

      // Verify ExcludeSemantics wraps the emoji text (at least 2 from our code)
      expect(find.byType(ExcludeSemantics), findsAtLeast(2));
    });

    testWidgets('cancel calls verification.cancel() and pops', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.waitingAccept,
      );
      await openDialog(tester, verification: verification);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(verification.cancelCalled, isTrue);
      // Dialog should be dismissed
      expect(find.byType(KeyVerificationDialog), findsNothing);
    });

    testWidgets('done state pops dialog', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.done,
      );
      await openDialog(tester, verification: verification);

      expect(find.text('Device verified successfully!'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(KeyVerificationDialog), findsNothing);
    });

    testWidgets('error state displays canceledReason', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.error,
        canceledReason: 'User rejected the keys',
      );
      await openDialog(tester, verification: verification);

      expect(find.text('User rejected the keys'), findsOneWidget);
      expect(find.text('Verification failed'), findsOneWidget);
    });

    testWidgets('askSSSS state shows unlocking message', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSSSS,
      );
      await openDialog(tester, verification: verification);

      expect(find.text('Unlocking encryption secrets...'), findsOneWidget);
    });

    testWidgets('askChoice auto-selects SAS verification', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.waitingAccept,
      );
      verification.possibleMethods = [EventTypes.Sas, EventTypes.QRShow];

      await openDialog(tester, verification: verification);

      // Transition to askChoice (e.g. other device supports QR + SAS)
      verification.simulateStateChange(KeyVerificationState.askChoice);
      await tester.pump();
      await tester.pump();

      // Should have auto-selected SAS
      expect(verification.continueVerificationMethod, EventTypes.Sas);
    });

    testWidgets('askChoice at dialog open auto-selects SAS', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
      );
      verification.possibleMethods = [EventTypes.Sas];

      await openDialog(tester, verification: verification);
      await tester.pump();

      expect(verification.continueVerificationMethod, EventTypes.Sas);
    });

    testWidgets('state transitions update the UI', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.waitingAccept,
      );
      await openDialog(tester, verification: verification);

      expect(find.text('Verify device'), findsOneWidget);

      // Simulate state change to done
      verification.simulateStateChange(KeyVerificationState.done);
      await tester.pump();

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Device verified successfully!'), findsOneWidget);
    });
  });
}
