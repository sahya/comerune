import 'package:comerune/data/follow/program_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractProviderName', () {
    test('returns name from programProvider', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      expect(extractProviderName(item), 'TestUser');
    });

    test('falls back to supplier name', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'supplier': <String, dynamic>{'name': 'SupplierUser'},
      };
      expect(extractProviderName(item), 'SupplierUser');
    });

    test('prefers programProvider over supplier', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{'name': 'Primary'},
        'supplier': <String, dynamic>{'name': 'Fallback'},
      };
      expect(extractProviderName(item), 'Primary');
    });

    test('returns null when neither is present', () {
      expect(extractProviderName(<String, dynamic>{}), isNull);
    });

    test('returns null for empty name', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{'name': ''},
      };
      expect(extractProviderName(item), isNull);
    });
  });

  group('extractProviderIconUrl', () {
    test('returns iconSmall from programProvider', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{
          'iconSmall': 'https://example.com/small.jpg',
        },
      };
      expect(extractProviderIconUrl(item), 'https://example.com/small.jpg');
    });

    test('falls back to icon from programProvider', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{
          'icon': 'https://example.com/icon.jpg',
        },
      };
      expect(extractProviderIconUrl(item), 'https://example.com/icon.jpg');
    });

    test('falls back to supplier uri50x50', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'supplier': <String, dynamic>{
          'icons': <String, dynamic>{'uri50x50': 'https://example.com/50.jpg'},
        },
      };
      expect(extractProviderIconUrl(item), 'https://example.com/50.jpg');
    });

    test('rejects non-HTTPS URLs', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{
          'iconSmall': 'http://example.com/insecure.jpg',
        },
      };
      expect(extractProviderIconUrl(item), isNull);
    });

    test('returns null when no icon available', () {
      expect(extractProviderIconUrl(<String, dynamic>{}), isNull);
    });

    test('falls back to supplier uri150x150 when uri50x50 missing', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'supplier': <String, dynamic>{
          'icons': <String, dynamic>{
            'uri150x150': 'https://example.com/150.jpg',
          },
        },
      };
      expect(extractProviderIconUrl(item), 'https://example.com/150.jpg');
    });

    test('falls back to programProvider icons.uri50x50', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'programProvider': <String, dynamic>{
          'icons': <String, dynamic>{
            'uri50x50': 'https://example.com/provider-50.jpg',
          },
        },
      };
      expect(
        extractProviderIconUrl(item),
        'https://example.com/provider-50.jpg',
      );
    });

    test('falls back to top-level iconUrl', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'iconUrl': 'https://example.com/direct-icon.jpg',
      };
      expect(
        extractProviderIconUrl(item),
        'https://example.com/direct-icon.jpg',
      );
    });

    test('falls back to generated nico icon URL from supplier ID', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'supplier': <String, dynamic>{'programProviderId': 18897569},
      };
      expect(
        extractProviderIconUrl(item),
        'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/1889/18897569.jpg',
      );
    });

    test('returns null when only non-numeric provider ID is available', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'supplier': <String, dynamic>{'programProviderId': 'ch2648853'},
      };
      expect(extractProviderIconUrl(item), isNull);
    });
  });

  group('extractCommunityName', () {
    test('returns name from socialGroup', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'socialGroup': <String, dynamic>{'name': 'TestCommunity'},
      };
      expect(extractCommunityName(item), 'TestCommunity');
    });

    test('returns null when no socialGroup', () {
      expect(extractCommunityName(<String, dynamic>{}), isNull);
    });

    test('returns null for empty community name', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'socialGroup': <String, dynamic>{'name': ''},
      };
      expect(extractCommunityName(item), isNull);
    });
  });

  group('isHttpsUrl', () {
    test('returns true for HTTPS URL', () {
      expect(isHttpsUrl('https://example.com'), isTrue);
    });

    test('returns false for HTTP URL', () {
      expect(isHttpsUrl('http://example.com'), isFalse);
    });

    test('returns false for empty string', () {
      expect(isHttpsUrl(''), isFalse);
    });
  });

  group('parseProgramItem', () {
    test('parses a complete program item', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{
          'name': 'TestUser',
          'iconSmall': 'https://example.com/icon.jpg',
        },
        'socialGroup': <String, dynamic>{'name': 'TestCommunity'},
      };

      final result = parseProgramItem(item);
      expect(result, isNotNull);
      expect(result!.programId, 'lv123456');
      expect(result.title, 'Test Title');
      expect(result.providerName, 'TestUser');
      expect(result.providerIconUrl, 'https://example.com/icon.jpg');
      expect(result.communityName, 'TestCommunity');
      expect(result.isOwnBroadcast, isFalse);
    });

    test('returns null when id is missing', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      expect(parseProgramItem(item), isNull);
    });

    test('returns null when title is missing', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      expect(parseProgramItem(item), isNull);
    });

    test('returns null when providerName missing and required', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
      };
      expect(parseProgramItem(item), isNull);
    });

    test('returns program when providerName missing but not required', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
      };
      final result = parseProgramItem(item, requireProviderName: false);
      expect(result, isNotNull);
      expect(result!.providerName, '');
    });

    test('sets isOwnBroadcast flag when specified', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      final result = parseProgramItem(item, isOwnBroadcast: true);
      expect(result, isNotNull);
      expect(result!.isOwnBroadcast, isTrue);
    });

    test('defaults isOwnBroadcast to false', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      final result = parseProgramItem(item);
      expect(result!.isOwnBroadcast, isFalse);
    });

    test('parses beginAt from ISO 8601 string', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
        'beginAt': '2026-03-30T10:00:00+09:00',
      };
      final result = parseProgramItem(item);
      expect(result, isNotNull);
      expect(result!.beginAt, isNotNull);
    });

    test('parses beginAt from Unix timestamp', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
        'beginAt': 1743307200,
      };
      final result = parseProgramItem(item);
      expect(result, isNotNull);
      expect(result!.beginAt, isNotNull);
    });

    test('beginAt is null when field is missing', () {
      final Map<String, dynamic> item = <String, dynamic>{
        'id': 'lv123456',
        'title': 'Test Title',
        'programProvider': <String, dynamic>{'name': 'TestUser'},
      };
      final result = parseProgramItem(item);
      expect(result!.beginAt, isNull);
    });
  });
}
