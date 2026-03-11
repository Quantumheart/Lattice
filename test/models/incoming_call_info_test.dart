import 'package:flutter_test/flutter_test.dart';

import 'package:lattice/features/calling/models/incoming_call_info.dart';

void main() {
  group('IncomingCallInfo', () {
    test('creates with required fields only', () {
      const info = IncomingCallInfo(roomId: '!room:example.com', callerName: 'Alice');
      expect(info.roomId, '!room:example.com');
      expect(info.callerName, 'Alice');
      expect(info.callId, isNull);
      expect(info.callerAvatarUrl, isNull);
      expect(info.isVideo, isFalse);
      expect(info.isGroupCall, isFalse);
    });

    test('creates with all fields', () {
      final avatarUrl = Uri.parse('mxc://example.com/avatar');
      final info = IncomingCallInfo(
        roomId: '!room:example.com',
        callerName: 'Bob',
        callId: 'call-123',
        callerAvatarUrl: avatarUrl,
        isVideo: true,
        isGroupCall: true,
      );
      expect(info.callId, 'call-123');
      expect(info.callerAvatarUrl, avatarUrl);
      expect(info.isVideo, isTrue);
      expect(info.isGroupCall, isTrue);
    });
  });

  group('CallType', () {
    test('has voice and video values', () {
      expect(CallType.values, containsAll([CallType.voice, CallType.video]));
      expect(CallType.values.length, 2);
    });
  });
}
