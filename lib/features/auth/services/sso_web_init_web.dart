import 'package:web/web.dart' as web;

Future<({String homeserver, String loginToken})?> checkPendingSsoLogin() async {
  final loginToken = Uri.base.queryParameters['loginToken'];
  final homeserver =
      web.window.sessionStorage.getItem('lattice_sso_homeserver');

  if (loginToken == null ||
      loginToken.isEmpty ||
      homeserver == null ||
      homeserver.isEmpty) {
    return null;
  }

  final base = Uri.base;
  final cleanUrl = Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.port,
    path: base.path,
  ).toString();
  web.window.history.replaceState(null, '', cleanUrl);
  web.window.sessionStorage.removeItem('lattice_sso_homeserver');

  return (homeserver: homeserver, loginToken: loginToken);
}
