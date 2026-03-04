import 'package:matrix/matrix.dart';

/// Returns a list of [Profile] objects for users the client has existing
/// direct-message rooms with. Useful for populating "recent contacts" in
/// DM and invite dialogs.
List<Profile> knownContacts(Client client) {
  final seen = <String>{};
  final contacts = <Profile>[];
  for (final room in client.rooms) {
    if (!room.isDirectChat) continue;
    final mxid = room.directChatMatrixID;
    if (mxid == null || !seen.add(mxid)) continue;
    contacts.add(Profile(
      userId: mxid,
      displayName: room.getLocalizedDisplayname(),
      avatarUrl: room.avatar,
    ));
  }
  return contacts;
}
