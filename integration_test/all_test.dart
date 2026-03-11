import 'package:integration_test/integration_test.dart';

import 'call_flow_suite.dart';
import 'chat_messaging_suite.dart';
import 'login_flow_suite.dart';
import 'room_management_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  loginFlowTests();
  roomManagementTests();
  chatMessagingTests();
  callFlowTests();
}
