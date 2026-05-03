import 'package:comerune/presentation/screens/login_screen.dart'
    show isAllowedLoginDomain, parseNicoUserSessionCookie;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAllowedLoginDomain', () {
    group('allows niconico domains', () {
      test('account.nicovideo.jp', () {
        expect(isAllowedLoginDomain('account.nicovideo.jp'), isTrue);
      });

      test('nicovideo.jp', () {
        expect(isAllowedLoginDomain('nicovideo.jp'), isTrue);
      });

      test('www.nicovideo.jp', () {
        expect(isAllowedLoginDomain('www.nicovideo.jp'), isTrue);
      });

      test('live.nicovideo.jp', () {
        expect(isAllowedLoginDomain('live.nicovideo.jp'), isTrue);
      });

      test('oauth.nicovideo.jp', () {
        expect(isAllowedLoginDomain('oauth.nicovideo.jp'), isTrue);
      });

      test('secure.nicovideo.jp', () {
        expect(isAllowedLoginDomain('secure.nicovideo.jp'), isTrue);
      });

      test('allows any subdomain of nicovideo.jp', () {
        expect(isAllowedLoginDomain('unknown.nicovideo.jp'), isTrue);
      });
    });

    group('allows OAuth provider domains', () {
      test('accounts.google.com for Google OAuth', () {
        expect(isAllowedLoginDomain('accounts.google.com'), isTrue);
      });

      test('api.x.com for X/Twitter OAuth', () {
        expect(isAllowedLoginDomain('api.x.com'), isTrue);
      });

      test('x.com for X/Twitter OAuth', () {
        expect(isAllowedLoginDomain('x.com'), isTrue);
      });

      test('twitter.com for legacy X/Twitter redirect', () {
        expect(isAllowedLoginDomain('twitter.com'), isTrue);
      });

      test('appleid.apple.com for Apple Sign-In', () {
        expect(isAllowedLoginDomain('appleid.apple.com'), isTrue);
      });

      test('accounts.nintendo.com for Nintendo Account', () {
        expect(isAllowedLoginDomain('accounts.nintendo.com'), isTrue);
      });

      test('access.line.me for LINE Login', () {
        expect(isAllowedLoginDomain('access.line.me'), isTrue);
      });

      test('liff.line.me for LINE Login', () {
        expect(isAllowedLoginDomain('liff.line.me'), isTrue);
      });

      test('login.yahoo.co.jp for Yahoo! JAPAN Login', () {
        expect(isAllowedLoginDomain('login.yahoo.co.jp'), isTrue);
      });

      test('auth.login.yahoo.co.jp for Yahoo! JAPAN OAuth callback', () {
        expect(isAllowedLoginDomain('auth.login.yahoo.co.jp'), isTrue);
      });
    });

    group('blocks unrelated domains', () {
      test('blocks example.com', () {
        expect(isAllowedLoginDomain('example.com'), isFalse);
      });

      test('blocks google.com (only accounts.google.com is allowed)', () {
        expect(isAllowedLoginDomain('google.com'), isFalse);
      });

      test('blocks mail.google.com', () {
        expect(isAllowedLoginDomain('mail.google.com'), isFalse);
      });

      test('blocks evil-nicovideo.jp (must end with .nicovideo.jp)', () {
        expect(isAllowedLoginDomain('evil-nicovideo.jp'), isFalse);
      });

      test('blocks empty string', () {
        expect(isAllowedLoginDomain(''), isFalse);
      });
    });
  });

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
