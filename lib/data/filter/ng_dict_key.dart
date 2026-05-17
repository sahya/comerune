import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Obfuscation key material for the bundled preset filter asset.
///
/// This is intentionally **not a security boundary**. A client-side app can
/// never keep an embedded key truly secret, so the only goal here is to stop
/// the casual "unzip the APK and read the JSON" extraction and to raise the
/// reverse-engineering cost. The key is split into fragments and reassembled
/// at runtime purely so that a plain string scan over the binary does not
/// trivially surface it next to the ciphertext.
///
/// The build-time tool (`tool/ng_dict.dart`) and the runtime loader both
/// derive the key from these exact fragments via [ngDictKey], so the
/// encrypted asset and the decrypter can never drift apart.
const List<String> _keyFragments = <String>[
  'cmrn1.7Qf2aZ8n',
  'P1xL0wKd5Hb3',
  'Vt9Ru4Sg2eMz',
  'Yj6Cn0Bx8Lk',
];

/// Derives the 32-byte preset-filter obfuscation key from the embedded
/// fragments. Returns a fresh list on every call so callers cannot mutate
/// shared state.
Uint8List ngDictKey() {
  final List<int> material = utf8.encode(_keyFragments.join('|'));
  return Uint8List.fromList(sha256.convert(material).bytes);
}
