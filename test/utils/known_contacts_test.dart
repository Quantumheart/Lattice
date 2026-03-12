import 'package:flutter_test/flutter_test.dart';
import 'package:lattice/core/utils/known_contacts.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'known_contacts_test.mocks.dart';

MockRoom _makeRoom({
  required bool isDirect,
  String? directChatMxid,
  String displayName = 'Room',
  Uri? avatar,
}) {
  final room = MockRoom();
  when(room.isDirectChat).thenReturn(isDirect);
  when(room.directChatMatrixID).thenReturn(directChatMxid);
  when(room.getLocalizedDisplayname()).thenReturn(displayName);
  when(room.avatar).thenReturn(avatar);
  return room;
}

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  test('returns empty list when client has no rooms', () {
    when(client.rooms).thenReturn([]);
    expect(knownContacts(client), isEmpty);
  });

  test('skips non-direct-chat rooms', () {
    final room = _makeRoom(isDirect: false, directChatMxid: '@user:example.com');
    when(client.rooms).thenReturn([room]);
    expect(knownContacts(client), isEmpty);
  });

  test('skips direct rooms with null matrixID', () {
    final room = _makeRoom(isDirect: true);
    when(client.rooms).thenReturn([room]);
    expect(knownContacts(client), isEmpty);
  });

  test('returns profile for a single DM room', () {
    final avatar = Uri.parse('mxc://example.com/abc');
    final room = _makeRoom(
      isDirect: true,
      directChatMxid: '@alice:example.com',
      displayName: 'Alice',
      avatar: avatar,
    );
    when(client.rooms).thenReturn([room]);

    final result = knownContacts(client);
    expect(result, hasLength(1));
    expect(result[0].userId, '@alice:example.com');
    expect(result[0].displayName, 'Alice');
    expect(result[0].avatarUrl, avatar);
  });

  test('deduplicates contacts with the same matrixID', () {
    final rooms = [
      _makeRoom(
        isDirect: true,
        directChatMxid: '@bob:example.com',
        displayName: 'Bob (old)',
      ),
      _makeRoom(
        isDirect: true,
        directChatMxid: '@bob:example.com',
        displayName: 'Bob (new)',
      ),
    ];
    when(client.rooms).thenReturn(rooms);

    final result = knownContacts(client);
    expect(result, hasLength(1));
    expect(result[0].displayName, 'Bob (old)');
  });

  test('returns multiple distinct contacts', () {
    final rooms = [
      _makeRoom(isDirect: true, directChatMxid: '@a:x.com', displayName: 'A'),
      _makeRoom(isDirect: false, directChatMxid: '@skip:x.com'),
      _makeRoom(isDirect: true, directChatMxid: '@b:x.com', displayName: 'B'),
      _makeRoom(isDirect: true, directChatMxid: '@c:x.com', displayName: 'C'),
    ];
    when(client.rooms).thenReturn(rooms);

    final result = knownContacts(client);
    expect(result, hasLength(3));
    expect(result.map((p) => p.userId), ['@a:x.com', '@b:x.com', '@c:x.com']);
  });
}
