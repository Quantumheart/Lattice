/// An SSO identity provider advertised by the homeserver.
class SsoIdentityProvider {
  final String id;
  final String name;
  final String? icon;

  const SsoIdentityProvider({
    required this.id,
    required this.name,
    this.icon,
  });
}

/// Describes what authentication methods a homeserver supports.
class ServerAuthCapabilities {
  final bool supportsPassword;
  final bool supportsSso;
  final bool supportsRegistration;
  final List<SsoIdentityProvider> ssoIdentityProviders;
  final List<String> registrationStages;

  /// The resolved homeserver URI after .well-known lookup.
  final Uri? resolvedHomeserver;

  const ServerAuthCapabilities({
    this.supportsPassword = false,
    this.supportsSso = false,
    this.supportsRegistration = false,
    this.ssoIdentityProviders = const [],
    this.registrationStages = const [],
    this.resolvedHomeserver,
  });
}
