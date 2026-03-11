import 'package:integration_test/integration_test.dart';

import 'call_flow_test.dart';
import 'chat_messaging_test.dart';
import 'login_flow_test.dart';
import 'room_management_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  loginFlowTests();
  roomManagementTests();
  chatMessagingTests();
  callFlowTests();
}
