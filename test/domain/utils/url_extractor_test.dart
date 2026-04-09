import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/url_extractor.dart';

void main() {
  group('findUrls', () {
    test('returns empty list for empty string', () {
      expect(findUrls(''), const <UrlMatch>[]);
    });

    test('returns empty list when no URL is present', () {
      expect(findUrls('普通のコメントです'), const <UrlMatch>[]);
    });

    test('extracts a single http URL', () {
      final List<UrlMatch> matches = findUrls('check http://example.com now');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'http://example.com');
      expect(matches.first.start, 6);
      expect(matches.first.end, 6 + 'http://example.com'.length);
    });

    test('extracts a single https URL', () {
      final List<UrlMatch> matches = findUrls('see https://example.com/path');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'https://example.com/path');
    });

    test('extracts multiple URLs in order', () {
      final List<UrlMatch> matches = findUrls(
        'first https://a.example then http://b.example done',
      );
      expect(matches, hasLength(2));
      expect(matches[0].url, 'https://a.example');
      expect(matches[1].url, 'http://b.example');
    });

    test('trims trailing period', () {
      final List<UrlMatch> matches = findUrls('see https://example.com.');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'https://example.com');
    });

    test('trims trailing Japanese punctuation', () {
      final List<UrlMatch> matches = findUrls('確認して→https://example.com、次へ');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'https://example.com');
    });

    test('trims trailing Japanese period', () {
      final List<UrlMatch> matches = findUrls('詳細は https://example.com 。');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'https://example.com');
    });

    test('trims trailing closing bracket without a matching open', () {
      final List<UrlMatch> matches = findUrls('(see https://example.com)');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'https://example.com');
    });

    test('keeps balanced parentheses inside a URL path', () {
      final List<UrlMatch> matches = findUrls(
        'see https://en.wikipedia.org/wiki/Dart_(programming_language) now',
      );
      expect(matches, hasLength(1));
      expect(
        matches.first.url,
        'https://en.wikipedia.org/wiki/Dart_(programming_language)',
      );
    });

    test('ignores URLs without a host', () {
      expect(findUrls('broken http:// comment'), const <UrlMatch>[]);
    });

    test('ignores non-http schemes even when they look like URLs', () {
      expect(findUrls('ftp://example.com data'), const <UrlMatch>[]);
      expect(findUrls('call javascript://alert(1) please'), const <UrlMatch>[]);
    });

    test('start and end cover the URL exactly in the original text', () {
      const String text = 'aa https://example.com/x bb';
      final List<UrlMatch> matches = findUrls(text);
      expect(matches, hasLength(1));
      final UrlMatch match = matches.first;
      expect(text.substring(match.start, match.end), match.url);
    });

    test('matches case-insensitively on the scheme', () {
      final List<UrlMatch> matches = findUrls('see HTTPS://Example.com');
      expect(matches, hasLength(1));
      expect(matches.first.url, 'HTTPS://Example.com');
    });
  });

  group('isSafeHttpUrl', () {
    test('accepts http URL', () {
      expect(isSafeHttpUrl('http://example.com'), isTrue);
    });

    test('accepts https URL', () {
      expect(isSafeHttpUrl('https://example.com/path?x=1'), isTrue);
    });

    test('rejects javascript scheme', () {
      expect(isSafeHttpUrl('javascript:alert(1)'), isFalse);
    });

    test('rejects file scheme', () {
      expect(isSafeHttpUrl('file:///etc/passwd'), isFalse);
    });

    test('rejects ftp scheme', () {
      expect(isSafeHttpUrl('ftp://example.com'), isFalse);
    });

    test('rejects intent scheme (Android intent URL)', () {
      expect(
        isSafeHttpUrl('intent://example.com#Intent;scheme=http;end'),
        isFalse,
      );
    });

    test('rejects schemeless string', () {
      expect(isSafeHttpUrl('example.com'), isFalse);
    });

    test('rejects empty host', () {
      expect(isSafeHttpUrl('http://'), isFalse);
    });

    test('rejects empty string', () {
      expect(isSafeHttpUrl(''), isFalse);
    });
  });
}
