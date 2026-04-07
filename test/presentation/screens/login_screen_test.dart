import 'package:comerune/presentation/screens/login_screen.dart'
    show isAllowedLoginDomain;
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
}
