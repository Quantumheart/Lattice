import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/notifications/services/call_push_rule_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>()])
import 'call_push_rule_manager_test.mocks.dart';

void main() {
  late MockClient mockClient;
  late CallPushRuleManager manager;

  setUp(() {
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@alice:example.com');
    manager = CallPushRuleManager(client: mockClient);
  });

  PushRule makeDesiredRule() => PushRule(
        ruleId: '.io.kohera.call_member',
        default$: false,
        enabled: true,
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: 'org.matrix.msc3401.call.member',
          ),
        ],
        actions: [
          'notify',
          {'set_tweak': 'sound', 'value': 'ring'},
          {'set_tweak': 'highlight', 'value': false},
        ],
      );

  test('writes rule when missing', () async {
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: []));
    when(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    ).thenAnswer((_) async {});

    await manager.ensureRule();

    verify(
      mockClient.setPushRule(
        PushRuleKind.override,
        '.io.kohera.call_member',
        any,
        conditions: anyNamed('conditions'),
      ),
    ).called(1);
  });

  test('no write when rule already present with matching actions', () async {
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: [makeDesiredRule()]));

    await manager.ensureRule();

    verifyNever(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    );
  });

  test('rewrites rule when actions differ', () async {
    final stale = PushRule(
      ruleId: '.io.kohera.call_member',
      default$: false,
      enabled: true,
      actions: ['dont_notify'],
    );
    when(mockClient.getPushRules())
        .thenAnswer((_) async => PushRuleSet(override: [stale]));
    when(
      mockClient.setPushRule(
        any,
        any,
        any,
        before: anyNamed('before'),
        after: anyNamed('after'),
        conditions: anyNamed('conditions'),
        pattern: anyNamed('pattern'),
      ),
    ).thenAnswer((_) async {});

    await manager.ensureRule();

    verify(
      mockClient.setPushRule(
        PushRuleKind.override,
        '.io.kohera.call_member',
        any,
        conditions: anyNamed('conditions'),
      ),
    ).called(1);
  });

  test('no-op when userID missing', () async {
    when(mockClient.userID).thenReturn(null);

    await manager.ensureRule();

    verifyNever(mockClient.getPushRules());
  });
}
