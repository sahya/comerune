import 'dart:convert';
import 'dart:typed_data';

import 'package:comerune/data/filter/ng_dict_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgDictCipher', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

    test('round-trips arbitrary content', () {
      final Uint8List plain = bytes('{"version":3,"categories":{}} 日本語 🎉');
      final Uint8List blob = encryptNgDict(plain);
      expect(decryptNgDict(blob), plain);
    });

    test('round-trips empty content', () {
      final Uint8List plain = Uint8List(0);
      final Uint8List blob = encryptNgDict(plain);
      expect(blob.length, 52, reason: 'header only when payload is empty');
      expect(decryptNgDict(blob), isEmpty);
    });

    test('round-trips content longer than one SHA-256 keystream block', () {
      // > 32 bytes forces the counter to advance past block 0, exercising the
      // multi-block keystream path.
      final Uint8List plain = bytes('A' * 200);
      expect(decryptNgDict(encryptNgDict(plain)), plain);
    });

    test('is deterministic: same input yields byte-identical blob', () {
      final Uint8List plain = bytes('stable content');
      expect(encryptNgDict(plain), encryptNgDict(plain));
    });

    test('different content yields a different blob', () {
      expect(
        encryptNgDict(bytes('content A')),
        isNot(encryptNgDict(bytes('content B'))),
      );
    });

    test('rejects a blob that is too short', () {
      expect(
        () => decryptNgDict(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<NgDictCipherException>()),
      );
    });

    test('rejects a blob with the wrong magic', () {
      final Uint8List blob = encryptNgDict(bytes('hello'));
      blob[0] = blob[0] ^ 0xFF;
      expect(() => decryptNgDict(blob), throwsA(isA<NgDictCipherException>()));
    });

    test('rejects a blob whose ciphertext was tampered with', () {
      final Uint8List blob = encryptNgDict(bytes('important dictionary'));
      // Flip a byte well past the 52-byte header so the MAC must catch it.
      blob[blob.length - 1] = blob[blob.length - 1] ^ 0x01;
      expect(
        () => decryptNgDict(blob),
        throwsA(
          isA<NgDictCipherException>().having(
            (NgDictCipherException e) => e.reason,
            'reason',
            'integrity check failed',
          ),
        ),
      );
    });

    test('rejects a blob whose MAC was tampered with', () {
      final Uint8List blob = encryptNgDict(bytes('payload'));
      blob[20] = blob[20] ^ 0x01; // first MAC byte
      expect(() => decryptNgDict(blob), throwsA(isA<NgDictCipherException>()));
    });

    test('exception message stays generic (no internal-structure leak)', () {
      try {
        decryptNgDict(Uint8List(10));
        fail('expected NgDictCipherException');
      } on NgDictCipherException catch (e) {
        expect(e.toString(), 'NgDictCipherException: blob too short');
        // Must not echo any payload/dictionary content.
        expect(e.reason.contains('{'), isFalse);
      }
    });
  });
}
