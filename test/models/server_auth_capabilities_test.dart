import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/server_auth_capabilities.dart';

void main() {
  group('ServerAuthCapabilities', () {
    test('defaults to no support', () {
      const caps = ServerAuthCapabilities();
      expect(caps.supportsPassword, isFalse);
      expect(caps.supportsSso, isFalse);
      expect(caps.supportsRegistration, isFalse);
      expect(caps.ssoIdentityProviders, isEmpty);
      expect(caps.registrationStages, isEmpty);
      expect(caps.resolvedHomeserver, isNull);
    });

    test('creates with all fields', () {
      final homeserver = Uri.parse('https://matrix.example.com');
      final caps = ServerAuthCapabilities(
        supportsPassword: true,
        supportsSso: true,
        supportsRegistration: true,
        ssoIdentityProviders: const [
          SsoIdentityProvider(id: 'google', name: 'Google', icon: 'https://g.co/icon'),
        ],
        registrationStages: const ['m.login.recaptcha', 'm.login.terms'],
        resolvedHomeserver: homeserver,
      );

      expect(caps.supportsPassword, isTrue);
      expect(caps.supportsSso, isTrue);
      expect(caps.supportsRegistration, isTrue);
      expect(caps.ssoIdentityProviders, hasLength(1));
      expect(caps.registrationStages, hasLength(2));
      expect(caps.resolvedHomeserver, homeserver);
    });
  });

  group('SsoIdentityProvider', () {
    test('creates with required fields only', () {
      const provider = SsoIdentityProvider(id: 'github', name: 'GitHub');
      expect(provider.id, 'github');
      expect(provider.name, 'GitHub');
      expect(provider.icon, isNull);
    });

    test('creates with icon', () {
      const provider = SsoIdentityProvider(
        id: 'gitlab',
        name: 'GitLab',
        icon: 'https://gitlab.com/icon.png',
      );
      expect(provider.icon, 'https://gitlab.com/icon.png');
    });
  });
}
