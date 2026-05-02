import 'dart:convert';
import 'dart:math';

/// Generates cryptographically-strong opaque `state` parameters for OIDC.
///
/// Output is base64url (no padding) of [defaultByteLength] random bytes.
/// 32 bytes = 256 bits of entropy, well above any practical guess budget
/// even for a high-rate online attacker. Storage is intentionally
/// short-lived (see `kOAuthStateMaxAge`) to keep the validation window tight.
abstract class OAuthStateGenerator {
  String generate();
}

class SecureOAuthStateGenerator implements OAuthStateGenerator {
  SecureOAuthStateGenerator({
    Random? random,
    int byteLength = defaultByteLength,
  }) : assert(byteLength > 0, 'byteLength must be positive'),
       _random = random ?? Random.secure(),
       _byteLength = byteLength;

  final Random _random;
  final int _byteLength;

  /// 256-bit entropy. Same length used by App Auth / OIDC client SDKs.
  static const int defaultByteLength = 32;

  @override
  String generate() {
    final bytes = List<int>.generate(_byteLength, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
