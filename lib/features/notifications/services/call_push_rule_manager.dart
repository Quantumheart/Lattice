import 'package:flutter/foundation.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/calling/services/rtc_membership_service.dart'
    show callMemberEventType;
import 'package:matrix/matrix.dart';

// Ensures the homeserver notifies Kohera's VoIP pusher on inbound
// m.call.member state events. Rule is written (or repaired) per-account on
// login and on sync reconnect so it works on any homeserver without admin
// config changes.

class CallPushRuleManager {
  CallPushRuleManager({required Client client}) : _client = client;

  final Client _client;

  Future<void> ensureRule() async {
    if (_client.userID == null) return;
    try {
      final rules = await _client.getPushRules();
      final existing = rules.override
          ?.where((r) => r.ruleId == kPushRuleCallMember)
          .firstOrNull;

      if (existing != null && _actionsMatch(existing.actions)) {
        return;
      }

      await _client.setPushRule(
        PushRuleKind.override,
        kPushRuleCallMember,
        _desiredActions(),
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: callMemberEventType,
          ),
        ],
      );
      debugPrint('[Kohera] Installed $kPushRuleCallMember push rule');
    } catch (e) {
      debugPrint('[Kohera] Failed to ensure call push rule: $e');
    }
  }

  List<Object?> _desiredActions() => [
        'notify',
        {'set_tweak': 'sound', 'value': 'ring'},
        {'set_tweak': 'highlight', 'value': false},
      ];

  bool _actionsMatch(List<Object?> actions) {
    if (actions.length != 3) return false;
    if (actions[0] != 'notify') return false;

    final sound = actions[1];
    if (sound is! Map) return false;
    if (sound['set_tweak'] != 'sound' || sound['value'] != 'ring') return false;

    final highlight = actions[2];
    if (highlight is! Map) return false;
    if (highlight['set_tweak'] != 'highlight' ||
        highlight['value'] != false) {
      return false;
    }
    return true;
  }
}
