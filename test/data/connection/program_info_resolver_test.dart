import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/connection/program_info_resolver.dart';
import 'package:comerune/domain/models/follow_program.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProgramInfoResolver', () {
    test('resolves NDGR viewUri from programinfo API', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'status': 'onAir',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BBzh6D87sTyy',
            },
          ],
          'title': 'Test Program',
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv350186414',
        userSession: 'user_session_abc123',
      );

      expect(
        result.viewUri.toString(),
        'https://mpn.live.nicovideo.jp/api/view/v4/BBzh6D87sTyy',
      );
      expect(result.title, 'Test Program');
      expect(result.supplierUserId, isNull);
      expect(result.broadcasterName, isNull);
      expect(result.beginAt, isNull);
      expect(result.programStatus, ProgramStatus.onAir);
      expect(result.isTimeshift, isFalse);

      expect(httpClient.requests, hasLength(1));
      final _CapturedRequest request = httpClient.requests[0];
      expect(
        request.uri.toString(),
        'https://live2.nicovideo.jp/watch/lv350186414/programinfo',
      );
      expect(request.headers['X-Niconico-Session'], 'user_session_abc123');
      expect(request.headers['User-Agent'], isNotNull);

      resolver.dispose();
    });

    test(
      'extracts programStatus=ended for timeshift programs (#639 cause 2)',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'status': 'ended',
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/TimeshiftXYZ',
              },
            ],
            'title': 'Past Program',
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );
        final ProgramInfo result = await resolver.resolve(
          lv: 'lv999',
          userSession: 'session',
        );

        expect(result.programStatus, ProgramStatus.ended);
        expect(result.isTimeshift, isTrue);
        expect(
          result.viewUri.toString(),
          'https://mpn.live.nicovideo.jp/api/view/v4/TimeshiftXYZ',
        );
        resolver.dispose();
      },
    );

    test(
      'programStatus is null when status field is missing or unknown',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            // No 'status' field.
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/Unknown',
              },
            ],
            'title': 'Unknown Status Program',
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );
        final ProgramInfo result = await resolver.resolve(
          lv: 'lv000',
          userSession: 'session',
        );

        expect(result.programStatus, isNull);
        expect(
          result.isTimeshift,
          isFalse,
          reason:
              'unknown status must be treated as "assume live" so callers '
              'preserve historical behaviour (Issue #639 follow-up).',
        );
        resolver.dispose();
      },
    );

    test('extracts broadcaster user ID from broadcaster array', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Broadcaster Program',
          'broadcaster': <Object?>[
            <String, Object?>{'id': 67890, 'name': '配信者A'},
          ],
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/Broadcaster',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv1000',
        userSession: 'session',
      );

      expect(result.title, 'Broadcaster Program');
      expect(result.supplierUserId, '67890');
      expect(result.broadcasterName, '配信者A');

      resolver.dispose();
    });

    test('extracts broadcaster user ID from broadcaster object '
        '(current niconive user-live shape)', () async {
      // Real-world payload shape observed at:
      //   GET https://live2.nicovideo.jp/watch/<lv>/programinfo
      // for niconive user-live broadcasts. `data.broadcaster` is a
      // single object, not an array, and `id` is a string.
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'User Live Program',
          'broadcaster': <String, Object?>{'id': '11111111', 'name': 'テスト配信者A'},
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/UserLive',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2000',
        userSession: 'session',
      );

      expect(result.title, 'User Live Program');
      expect(result.supplierUserId, '11111111');
      expect(result.broadcasterName, 'テスト配信者A');

      resolver.dispose();
    });

    test('extracts broadcaster user ID from object with int id '
        '(type tolerance)', () async {
      // Same shape as the user-live response, but `id` is an int rather
      // than a string. The extractor should normalise via toString().
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Int Id Object',
          'broadcaster': <String, Object?>{'id': 12345678, 'name': '配信者X'},
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/IntId',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2100',
        userSession: 'session',
      );

      expect(result.supplierUserId, '12345678');
      expect(result.broadcasterName, '配信者X');

      resolver.dispose();
    });

    test('falls back to supplier when broadcaster object is empty', () async {
      // broadcaster is an empty object — neither id nor name available.
      // supplier should be consulted as fallback.
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Empty Broadcaster Object',
          'broadcaster': <String, Object?>{},
          'supplier': <String, Object?>{
            'name': 'サプライヤー',
            'programProviderId': 99999,
          },
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/EmptyB',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2200',
        userSession: 'session',
      );

      expect(result.supplierUserId, '99999');
      expect(result.broadcasterName, 'サプライヤー');

      resolver.dispose();
    });

    test(
      'returns null broadcaster info when broadcaster is an empty array',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Empty Array',
            'broadcaster': <Object?>[],
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/EmptyArr',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv2300',
          userSession: 'session',
        );

        expect(result.supplierUserId, isNull);
        expect(result.broadcasterName, isNull);

        resolver.dispose();
      },
    );

    test(
      'prefers broadcaster object over supplier when both present',
      () async {
        // When `broadcaster` is provided as an object with both id and
        // name, the supplier section must not override either.
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Object Wins',
            'broadcaster': <String, Object?>{'id': '11111', 'name': '本来の配信者'},
            'supplier': <String, Object?>{
              'name': '違う名前',
              'programProviderId': 22222,
            },
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/ObjectWins',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv2400',
          userSession: 'session',
        );

        expect(result.supplierUserId, '11111');
        expect(result.broadcasterName, '本来の配信者');

        resolver.dispose();
      },
    );

    test(
      'falls back to supplier name and ID when broadcaster is absent',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Supplier Fallback',
            'supplier': <String, Object?>{
              'name': 'テスト配信者',
              'programProviderId': 12345,
            },
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/TestSupplier',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv999',
          userSession: 'session',
        );

        expect(result.title, 'Supplier Fallback');
        expect(result.supplierUserId, '12345');
        expect(result.broadcasterName, 'テスト配信者');

        resolver.dispose();
      },
    );

    test('prefers broadcaster over supplier when both exist', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Both Present',
          'broadcaster': <Object?>[
            <String, Object?>{'id': 11111, 'name': '配信者B'},
          ],
          'supplier': <String, Object?>{'programProviderId': 22222},
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BothPresent',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv1001',
        userSession: 'session',
      );

      expect(result.supplierUserId, '11111');
      expect(result.broadcasterName, '配信者B');

      resolver.dispose();
    });

    test(
      'returns null supplierUserId when neither broadcaster nor supplier has ID',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'No IDs',
            'broadcaster': <Object?>[
              <String, Object?>{'name': '名前だけ'},
            ],
            'supplier': <String, Object?>{'name': 'テスト配信者'},
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/NoIds',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv888',
          userSession: 'session',
        );

        expect(result.title, 'No IDs');
        expect(result.supplierUserId, isNull);
        // broadcaster[0].name is preferred over supplier.name even without id.
        expect(result.broadcasterName, '名前だけ');

        resolver.dispose();
      },
    );

    test(
      'extracts broadcaster name when id is absent and no supplier exists',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Name Only Broadcaster',
            'broadcaster': <Object?>[
              <String, Object?>{'name': '配信者のみ'},
            ],
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/NameOnly',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv777',
          userSession: 'session',
        );

        expect(result.title, 'Name Only Broadcaster');
        expect(result.supplierUserId, isNull);
        expect(result.broadcasterName, '配信者のみ');

        resolver.dispose();
      },
    );

    test('uses supplier userId when broadcaster has name but no id', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Mixed Sources',
          'broadcaster': <Object?>[
            <String, Object?>{'name': '配信者C'},
          ],
          'supplier': <String, Object?>{
            'programProviderId': 99999,
            'name': 'サプライヤー名',
          },
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/MixedSrc',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv776',
        userSession: 'session',
      );

      // broadcaster name preferred, supplier userId used as fallback.
      expect(result.broadcasterName, '配信者C');
      expect(result.supplierUserId, '99999');

      resolver.dispose();
    });

    test('uses supplier name when broadcaster has id but no name', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Id Only Broadcaster',
          'broadcaster': <Object?>[
            <String, Object?>{'id': 55555},
          ],
          'supplier': <String, Object?>{'name': 'サプライヤー補完名'},
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/IdOnly',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv775',
        userSession: 'session',
      );

      // broadcaster id used, supplier name used as fallback.
      expect(result.supplierUserId, '55555');
      expect(result.broadcasterName, 'サプライヤー補完名');

      resolver.dispose();
    });

    test('extracts beginAt from ISO 8601 string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'BeginAt Program',
          'beginAt': '2025-07-01T12:00:00+09:00',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BeginAtTest',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2000',
        userSession: 'session',
      );

      expect(result.beginAt, isNotNull);
      expect(result.beginAt, isA<DateTime>());
      // 2025-07-01T12:00:00+09:00 == 2025-07-01T03:00:00Z
      expect(result.beginAt!.toUtc(), DateTime.utc(2025, 7, 1, 3, 0, 0));

      resolver.dispose();
    });

    test('returns null beginAt when field is absent', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'No BeginAt',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/NoBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2001',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('extracts beginAt from integer (seconds since epoch)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // 1719828000 == 2024-07-01T10:00:00Z
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'BeginAt Integer',
          'beginAt': 1719828000,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/BeginAtInt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2002',
        userSession: 'session',
      );

      expect(result.beginAt, isNotNull);
      expect(result.beginAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 0, 0));

      resolver.dispose();
    });

    test('returns null beginAt for empty string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Empty BeginAt',
          'beginAt': '',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/EmptyBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2003',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for invalid date string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Invalid BeginAt',
          'beginAt': 'not-a-date',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/InvalidBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2004',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt when value is explicit null', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Null BeginAt',
          'beginAt': null,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/NullBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2005',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for unexpected type (bool)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Bool BeginAt',
          'beginAt': true,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BoolBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2006',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for float value', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Float BeginAt',
          'beginAt': 1719828000.5,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/FloatBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2007',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    group('vposBaseAt (Issue #465)', () {
      test('extracts vposBaseAt from programSchedule.vposBaseTime '
          '(seconds epoch)', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'vpos test',
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V1',
              },
            ],
            'programSchedule': <String, Object?>{
              'vposBaseTime': 1719828060, // 2024-07-01 10:01:00Z
            },
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv100',
          userSession: 'session',
        );

        expect(result.vposBaseAt, isNotNull);
        expect(result.vposBaseAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 1, 0));

        resolver.dispose();
      });

      test('extracts vposBaseAt from programSchedule.vposBaseTime '
          '(ISO 8601 string)', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V2',
              },
            ],
            'programSchedule': <String, Object?>{
              'vposBaseTime': '2025-07-01T12:00:00+09:00',
            },
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv101',
          userSession: 'session',
        );

        expect(result.vposBaseAt, isNotNull);
        expect(result.vposBaseAt!.toUtc(), DateTime.utc(2025, 7, 1, 3, 0, 0));

        resolver.dispose();
      });

      test('extracts vposBaseAt from programSchedule.vposBaseTime '
          '(milliseconds epoch)', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        // 1719828060000 == 2024-07-01T10:01:00Z (milliseconds since epoch).
        // Locks the 13+-digit branch of parseDateTimeFlexible against
        // regressions where the threshold is moved or removed.
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V1ms',
              },
            ],
            'programSchedule': <String, Object?>{'vposBaseTime': 1719828060000},
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv100ms',
          userSession: 'session',
        );

        expect(result.vposBaseAt, isNotNull);
        expect(result.vposBaseAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 1, 0));

        resolver.dispose();
      });

      test('falls back to top-level data.vposBaseAt when programSchedule '
          'is absent', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V3',
              },
            ],
            'vposBaseAt': 1719828120, // 2024-07-01 10:02:00Z
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv102',
          userSession: 'session',
        );

        expect(result.vposBaseAt, isNotNull);
        expect(result.vposBaseAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 2, 0));

        resolver.dispose();
      });

      test('vposBaseAt is null when neither programSchedule nor top-level '
          'field is present — beginAt fallback preserved', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V4',
              },
            ],
            'beginAt': 1719828000,
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv103',
          userSession: 'session',
        );

        expect(
          result.vposBaseAt,
          isNull,
          reason:
              'no vpos base field is present; caller falls back to '
              'beginAt via computeVpos()',
        );
        expect(result.beginAt, isNotNull);

        resolver.dispose();
      });

      test('invalid vposBaseTime shapes (float / bool / empty string) are '
          'rejected and vposBaseAt stays null', () async {
        // Three shapes that would yield a garbage DateTime if accepted
        // uncritically. Run them sequentially against the same resolver
        // instance (distinct responses) to lock the strict parsing.
        const List<Object?> badShapes = <Object?>[
          1719828000.5, // float
          true, // bool
          '', // empty string
          'not-a-date', // unparseable string
          <String>[], // list
          <String, Object?>{}, // nested map
        ];

        for (final Object? bad in badShapes) {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseBody = jsonEncode(<String, Object?>{
            'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
            'data': <String, Object?>{
              'rooms': <Object?>[
                <String, Object?>{
                  'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V5',
                },
              ],
              'programSchedule': <String, Object?>{'vposBaseTime': bad},
            },
          });

          final ProgramInfoResolver resolver = ProgramInfoResolver(
            httpClient: httpClient,
          );

          final ProgramInfo result = await resolver.resolve(
            lv: 'lv104',
            userSession: 'session',
          );

          expect(
            result.vposBaseAt,
            isNull,
            reason:
                'bad shape ${bad.runtimeType} ($bad) must be rejected so '
                'comment vpos stays on the safe beginAt fallback rather '
                'than decoding garbage timestamps.',
          );

          resolver.dispose();
        }
      });

      test('programSchedule.vposBaseTime takes precedence over the '
          'top-level vposBaseAt fallback when both are present', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/V6',
              },
            ],
            // Primary path: programSchedule.vposBaseTime → 10:03:00Z.
            'programSchedule': <String, Object?>{'vposBaseTime': 1719828180},
            // Fallback path: data.vposBaseAt → 10:04:00Z. Must be
            // ignored because the primary path is populated.
            'vposBaseAt': 1719828240,
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv105',
          userSession: 'session',
        );

        expect(result.vposBaseAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 3, 0));

        resolver.dispose();
      });
    });

    test(
      'sends request without auth headers when user_session is empty',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Public Program',
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/PublicTest',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(lv: 'lv123');
        expect(result.title, 'Public Program');

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        // No auth headers should be set.
        expect(request.headers['Cookie'], isNull);
        expect(request.headers['X-Niconico-Session'], isNull);
        expect(request.headers['User-Agent'], isNotNull);

        resolver.dispose();
      },
    );

    test('throws when API returns non-200', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseStatusCode = 401;
      httpClient.responseBody = 'Unauthorized';

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when response has no rooms', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{'status': 'onAir', 'rooms': <Object?>[]},
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when room has no viewUri', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'rooms': <Object?>[<String, Object?>{}],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });
  });

  group('ProgramInfoResolveException', () {
    test('toString includes message', () {
      final ProgramInfoResolveException exception = ProgramInfoResolveException(
        'test error',
      );
      expect(exception.toString(), 'ProgramInfoResolveException: test error');
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(uri: url, client: this);
  }

  @override
  set connectionTimeout(Duration? timeout) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.uri, required this.client});

  @override
  final Uri uri;
  final _FakeHttpClient client;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    final Map<String, String> headerMap = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        headerMap[key] = values.first;
      }
    });

    client.requests.add(_CapturedRequest(uri: uri, headers: headerMap));

    return _FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = <String>[value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => <String>[]).add(value.toString());
  }

  @override
  List<String>? operator [](String name) {
    return _values[name];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required String body})
    : _body = body;

  @override
  final int statusCode;
  final String _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(_body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
