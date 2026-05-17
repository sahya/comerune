/// Lightweight obfuscation codec for the bundled preset NG-word asset.
///
/// Threat model (deliberately modest): prevent the casual "unzip the APK and
/// read the JSON" extraction and raise the reverse-engineering cost. It is
/// **not** a cryptographic secrecy guarantee — the key is embedded in the
/// binary (see [ngDictKey]), so a determined reverse engineer can recover it.
/// The construction below is a SHA-256 counter-mode keystream XOR with an
/// HMAC-SHA256 tag for tamper-evidence, built only on `package:crypto`
/// (no extra supply-chain dependency) per the project dependency policy.
/// The keystream and the MAC use **separate domain-separated subkeys** both
/// derived from the embedded master key, so the same key material is never
/// reused across the two primitives (key-separation hygiene; also keeps the
/// construction from being a poor template if copied elsewhere).
///
/// Blob layout (all big-endian, no padding):
///
/// ```
/// offset 0  magic      4 bytes  ASCII "CMR1"
/// offset 4  salt      16 bytes  = SHA-256(plaintext)[0..16]  (deterministic)
/// offset 20 mac       32 bytes  = HMAC-SHA256(macKey, magic||salt||ciphertext)
/// offset 52 ciphertext N bytes  = plaintext XOR keystream(encKey, salt)
/// ```
///
/// The salt is derived from the plaintext so re-encrypting unchanged content
/// produces a byte-identical blob (reproducible builds, clean git diffs). The
/// salt is not secret; it only needs to vary per dictionary revision so the
/// keystream differs across versions.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ng_dict_key.dart';

const List<int> _magic = <int>[0x43, 0x4d, 0x52, 0x31]; // "CMR1"
const int _saltLength = 16;
const int _macLength = 32;
const int _headerLength = 4 + _saltLength + _macLength; // 52

// Domain-separation labels so the keystream PRF and the HMAC derive
// independent subkeys from the same embedded master key.
const String _encKeyLabel = 'ng-dict/enc/v1';
const String _macKeyLabel = 'ng-dict/mac/v1';

/// Thrown when [decryptNgDict] is given a blob that is missing, truncated,
/// has the wrong magic, or fails the integrity (MAC) check.
///
/// The message is deliberately generic so it never leaks anything about the
/// asset's internal structure into logs.
class NgDictCipherException implements Exception {
  const NgDictCipherException(this.reason);

  final String reason;

  @override
  String toString() => 'NgDictCipherException: $reason';
}

/// Encrypts [plaintext] into the on-disk blob format. Pure and deterministic:
/// the same input always yields the same output.
Uint8List encryptNgDict(Uint8List plaintext) {
  final Uint8List master = ngDictKey();
  final Uint8List encKey = _subKey(master, _encKeyLabel);
  final Uint8List macKey = _subKey(master, _macKeyLabel);
  final Uint8List salt = Uint8List.fromList(
    sha256.convert(plaintext).bytes.sublist(0, _saltLength),
  );
  final Uint8List keystream = _keystream(encKey, salt, plaintext.length);
  final Uint8List ciphertext = Uint8List(plaintext.length);
  for (int i = 0; i < plaintext.length; i++) {
    ciphertext[i] = plaintext[i] ^ keystream[i];
  }
  final Uint8List mac = _mac(macKey, salt, ciphertext);

  final BytesBuilder builder = BytesBuilder(copy: false)
    ..add(_magic)
    ..add(salt)
    ..add(mac)
    ..add(ciphertext);
  return builder.toBytes();
}

/// Decrypts a blob produced by [encryptNgDict]. Throws
/// [NgDictCipherException] on any structural or integrity failure; callers
/// are expected to fall back to an empty preset list (defense-in-depth, the
/// app must keep running even if the asset is missing or corrupt).
Uint8List decryptNgDict(Uint8List blob) {
  if (blob.length < _headerLength) {
    throw const NgDictCipherException('blob too short');
  }
  for (int i = 0; i < _magic.length; i++) {
    if (blob[i] != _magic[i]) {
      throw const NgDictCipherException('bad magic');
    }
  }
  final Uint8List master = ngDictKey();
  final Uint8List encKey = _subKey(master, _encKeyLabel);
  final Uint8List macKey = _subKey(master, _macKeyLabel);
  final Uint8List salt = Uint8List.sublistView(blob, 4, 4 + _saltLength);
  final Uint8List mac = Uint8List.sublistView(
    blob,
    4 + _saltLength,
    _headerLength,
  );
  final Uint8List ciphertext = Uint8List.sublistView(blob, _headerLength);

  final Uint8List expectedMac = _mac(macKey, salt, ciphertext);
  if (!_constantTimeEquals(mac, expectedMac)) {
    throw const NgDictCipherException('integrity check failed');
  }

  final Uint8List keystream = _keystream(encKey, salt, ciphertext.length);
  final Uint8List plaintext = Uint8List(ciphertext.length);
  for (int i = 0; i < ciphertext.length; i++) {
    plaintext[i] = ciphertext[i] ^ keystream[i];
  }
  return plaintext;
}

/// Domain-separated subkey: SHA-256(master || label). Ensures the keystream
/// PRF and the HMAC never share key material (key-separation hygiene).
Uint8List _subKey(Uint8List master, String label) {
  final BytesBuilder builder = BytesBuilder(copy: false)
    ..add(master)
    ..add(label.codeUnits);
  return Uint8List.fromList(sha256.convert(builder.toBytes()).bytes);
}

Uint8List _mac(Uint8List key, Uint8List salt, Uint8List ciphertext) {
  final Hmac hmac = Hmac(sha256, key);
  final BytesBuilder builder = BytesBuilder(copy: false)
    ..add(_magic)
    ..add(salt)
    ..add(ciphertext);
  return Uint8List.fromList(hmac.convert(builder.toBytes()).bytes);
}

/// SHA-256 counter-mode keystream: block `i` = SHA-256(key || salt || i_be32).
Uint8List _keystream(Uint8List key, Uint8List salt, int length) {
  final Uint8List out = Uint8List(length);
  int offset = 0;
  int counter = 0;
  while (offset < length) {
    final Uint8List counterBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, counter, Endian.big);
    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(key)
      ..add(salt)
      ..add(counterBytes);
    final List<int> block = sha256.convert(builder.toBytes()).bytes;
    final int take = (length - offset) < block.length
        ? (length - offset)
        : block.length;
    out.setRange(offset, offset + take, block);
    offset += take;
    counter++;
  }
  return out;
}

/// Length-independent, content-constant-time comparison. Both inputs are
/// fixed-length MAC digests so leaking the length is not a concern; the loop
/// avoids an early-exit timing signal on the digest contents.
bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  int diff = 0;
  for (int i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
