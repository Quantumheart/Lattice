import 'package:flutter_test/flutter_test.dart';

import 'package:kohera/features/calling/models/call_constants.dart';

void main() {
  group('callEventTypes', () {
    test('contains all signaling event types', () {
      expect(callEventTypes, contains(kCallInvite));
      expect(callEventTypes, contains(kCallAnswer));
      expect(callEventTypes, contains(kCallHangup));
      expect(callEventTypes, contains(kCallReject));
    });

    test('has exactly 4 event types', () {
      expect(callEventTypes.length, 4);
    });

    test('does not contain member event types', () {
      expect(callEventTypes, isNot(contains(kCallMember)));
      expect(callEventTypes, isNot(contains(kCallMemberMsc)));
    });
  });

  group('constants have expected values', () {
    test('event type strings', () {
      expect(kCallInvite, 'm.call.invite');
      expect(kCallAnswer, 'm.call.answer');
      expect(kCallHangup, 'm.call.hangup');
      expect(kCallReject, 'm.call.reject');
      expect(kCallMember, 'com.famedly.call.member');
      expect(kCallMemberMsc, 'org.matrix.msc3401.call.member');
    });

    test('hangup reason strings', () {
      expect(kHangupUserHangup, 'user_hangup');
      expect(kHangupInviteTimeout, 'invite_timeout');
    });
  });
}
