import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/auth/oauth_bff/oauth_state_generator.dart';

void main() {
  group('SecureOAuthStateGenerator', () {
    test('default 32-byte output is 43-char base64url with no padding', () {
      final gen = SecureOAuthStateGenerator();
      final s = gen.generate();
      expect(
        s.length,
        43,
        reason: 'base64url(32 bytes) without "=" padding is exactly 43 chars',
      );
      expect(s.contains('='), isFalse);
      // base64url alphabet: A-Z a-z 0-9 - _
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s), isTrue);
      // Round-trip decode succeeds.
      final padded = s + ('=' * ((4 - s.length % 4) % 4));
      expect(base64Url.decode(padded).length, 32);
    });

    test('two consecutive generate() calls produce distinct values', () {
      final gen = SecureOAuthStateGenerator();
      expect(gen.generate(), isNot(equals(gen.generate())));
    });

    test('respects custom byteLength', () {
      final gen = SecureOAuthStateGenerator(byteLength: 16);
      final s = gen.generate();
      // base64url(16 bytes) = 22 chars (after stripping "==" padding).
      expect(s.length, 22);
    });

    test(
      'with a seeded Random, output is deterministic (no real entropy in tests)',
      () {
        final a = SecureOAuthStateGenerator(random: Random(42));
        final b = SecureOAuthStateGenerator(random: Random(42));
        expect(a.generate(), b.generate());
      },
    );

    test('byteLength 0 is rejected by assertion', () {
      expect(
        () => SecureOAuthStateGenerator(byteLength: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
