import 'package:matrix/matrix.dart';

/// Returns auth headers only if [url] points to the same host as the
/// homeserver, preventing token leakage to federated media servers.
Map<String, String>? mediaAuthHeaders(Client client, String url) {
  try {
    final uri = Uri.parse(url);
    final homeserver = client.homeserver;
    if (homeserver != null && uri.host == homeserver.host) {
      return {'authorization': 'Bearer ${client.accessToken}'};
    }
  } catch (_) {}
  return null;
}
