/// Compile-time configuration for the OIDC authorization flow.
///
/// Non-secret host / scope values are injected at build time so that public
/// repository forks do not inherit production identifiers and the same
/// values are not duplicated across the Flutter and Android sides.
///
/// **Recommended**: provision `android/oauth_bff.env` (gitignored; see
/// `android/oauth_bff.env.example`) and pass it once via
///
///   flutter build apk --dart-define-from-file=android/oauth_bff.env
///
/// The same file is also read by `android/app/build.gradle.kts` to inject
/// `OAUTH_BFF_HOST` into the AndroidManifest App Links intent-filter, so
/// the Flutter and Android sides stay in sync.
///
/// The keys consumed are:
///
///   NICONICO_OAUTH_CLIENT_ID
///   OAUTH_BFF_HOST
///   OAUTH_AUTHORIZE_ENDPOINT
///
/// Individual `--dart-define=KEY=VALUE` flags are equivalent if you prefer
/// not to use the file form.
///
/// The OAuth `client_secret` is **never** read by the app — it is held
/// server-side in the BFF and the BFF's environment variables only.
class OAuthBffConfig {
  const OAuthBffConfig({
    required this.clientId,
    required this.authorizeEndpoint,
    required this.bffTokenEndpoint,
    required this.redirectUri,
    required this.scope,
  });

  /// Default production configuration. `clientId`, the BFF host, and the
  /// upstream authorize endpoint are all empty unless built with the
  /// matching `--dart-define`s; the auth service throws fast in that case
  /// so the misconfiguration is loud, and UI can additionally pre-check
  /// [isFullyConfigured] to hide the login entry point on builds that
  /// lack any of the three values.
  static OAuthBffConfig production() {
    const String bffHost = String.fromEnvironment(
      'OAUTH_BFF_HOST',
      defaultValue: '',
    );
    return OAuthBffConfig(
      clientId: const String.fromEnvironment(
        'NICONICO_OAUTH_CLIENT_ID',
        defaultValue: '',
      ),
      authorizeEndpoint: const String.fromEnvironment(
        'OAUTH_AUTHORIZE_ENDPOINT',
        defaultValue: '',
      ),
      bffTokenEndpoint: bffHost.isEmpty ? '' : 'https://$bffHost/api/token',
      redirectUri: bffHost.isEmpty ? '' : 'https://$bffHost/auth/callback',
      scope: 'openid user',
    );
  }

  final String clientId;
  final String authorizeEndpoint;
  final String bffTokenEndpoint;
  final String redirectUri;
  final String scope;

  /// Whether the build was produced with a non-empty `clientId` (i.e. the
  /// `--dart-define=NICONICO_OAUTH_CLIENT_ID=...` was supplied at build
  /// time).
  bool get isClientIdConfigured => clientId.isNotEmpty;

  /// Whether the build was produced with a non-empty BFF host (i.e. the
  /// `--dart-define=OAUTH_BFF_HOST=...` was supplied at build time).
  /// Implemented by checking the derived endpoint string so a single
  /// emptiness check covers both `bffTokenEndpoint` and `redirectUri`.
  bool get isBffHostConfigured => bffTokenEndpoint.isNotEmpty;

  /// Whether the build was produced with a non-empty upstream authorize
  /// endpoint (i.e. the `--dart-define=OAUTH_AUTHORIZE_ENDPOINT=...` was
  /// supplied at build time).
  bool get isAuthorizeEndpointConfigured => authorizeEndpoint.isNotEmpty;

  /// Convenience: `client_id`, BFF host, and authorize endpoint are all
  /// present. UI / wiring code should consult this before exposing the
  /// OAuth login entry point so a misconfigured release build does not
  /// let users tap a button that can only fail.
  bool get isFullyConfigured =>
      isClientIdConfigured &&
      isBffHostConfigured &&
      isAuthorizeEndpointConfigured;
}
