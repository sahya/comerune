import 'package:comerune/presentation/screens/login_screen.dart'
    show parseNicoUserSessionCookie;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNicoUserSessionCookie', () {
    test('extracts user_session cookie', () {
      expect(
        parseNicoUserSessionCookie(
          'nicosid=12345; user_session=abc123; other=xyz',
        ),
        'abc123',
      );
    });

    test('extracts user_session_XXXXX cookie', () {
      expect(
        parseNicoUserSessionCookie(
          'nicosid=12345; user_session_98765432=session_value; other=xyz',
        ),
        'session_value',
      );
    });

    test('ignores user_session_secure cookie', () {
      expect(
        parseNicoUserSessionCookie(
          'user_session_secure=secret; user_session=good_value',
        ),
        'good_value',
      );
    });

    test('ignores user_session_secure_XXXXX cookie', () {
      expect(
        parseNicoUserSessionCookie(
          'user_session_secure_98765432=secret; user_session_98765432=good',
        ),
        'good',
      );
    });

    test('returns null when no user_session cookie exists', () {
      expect(parseNicoUserSessionCookie('nicosid=12345; other=xyz'), isNull);
    });

    test('returns null for empty cookie string', () {
      expect(parseNicoUserSessionCookie(''), isNull);
    });

    test('returns null when user_session value is empty', () {
      expect(parseNicoUserSessionCookie('user_session='), isNull);
    });

    test('handles cookie string with extra whitespace', () {
      expect(
        parseNicoUserSessionCookie('  user_session = abc123 ;  other = xyz  '),
        isNull, // "user_session " (with space) won't match exact name
      );
    });

    test('handles single cookie without semicolons', () {
      expect(parseNicoUserSessionCookie('user_session=only_one'), 'only_one');
    });

    test('prefers first matching cookie', () {
      expect(
        parseNicoUserSessionCookie('user_session=first; user_session=second'),
        'first',
      );
    });
  });
}
