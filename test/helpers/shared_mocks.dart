import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
  MockSpec<Timeline>(),
  MockSpec<FlutterSecureStorage>(),
])
export 'shared_mocks.mocks.dart';
