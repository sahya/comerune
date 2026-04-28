import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/data/comment/live_comment_repository.dart';
import 'package:comerune/data/follow/my_program_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentPostController.validateText', () {
    test('returns empty for blank text', () {
      expect(
        CommentPostController.validateText(text: '', asOperator: false),
        CommentValidationError.empty,
      );
      expect(
        CommentPostController.validateText(text: '   ', asOperator: true),
        CommentValidationError.empty,
      );
    });

    test('returns invisibleOnly for input that sanitises to empty', () {
      expect(
        CommentPostController.validateText(
          text: '\u200B\u202E\uFEFF',
          asOperator: false,
        ),
        CommentValidationError.invisibleOnly,
      );
    });

    test('returns invisibleOnly for ZWSP-only input (not empty)', () {
      expect(
        CommentPostController.validateText(text: '\u200B', asOperator: true),
        CommentValidationError.invisibleOnly,
      );
    });

    test('returns empty for NBSP-only input (Dart trim strips NBSP)', () {
      expect(
        CommentPostController.validateText(text: '\u00A0', asOperator: false),
        CommentValidationError.empty,
      );
    });

    test(
      'returns invisibleOnly for NBSP mixed with visible-length invisible chars',
      () {
        // ZWSP passes trim() (not considered whitespace) but is stripped by
        // removeControlAndInvisibleChars, producing an invisibleOnly result.
        expect(
          CommentPostController.validateText(
            text: '\u200B\u00AD',
            asOperator: false,
          ),
          CommentValidationError.invisibleOnly,
        );
      },
    );

    test('returns null for input with visible chars after sanitisation', () {
      expect(
        CommentPostController.validateText(
          text: 'hello\u200B',
          asOperator: false,
        ),
        isNull,
      );
    });

    test('returns tooLong when normal comment exceeds 75 chars', () {
      final String text = 'a' * 76;
      expect(
        CommentPostController.validateText(text: text, asOperator: false),
        CommentValidationError.tooLong,
      );
    });

    test('allows exactly 75 chars for normal comment', () {
      final String text = 'a' * 75;
      expect(
        CommentPostController.validateText(text: text, asOperator: false),
        isNull,
      );
    });

    test('returns tooLong when operator comment exceeds 100 chars', () {
      final String text = 'a' * 101;
      expect(
        CommentPostController.validateText(text: text, asOperator: true),
        CommentValidationError.tooLong,
      );
    });

    test('allows exactly 100 chars for operator comment', () {
      final String text = 'a' * 100;
      expect(
        CommentPostController.validateText(text: text, asOperator: true),
        isNull,
      );
    });

    test('honours injected maxLength over the default operator limit', () {
      // When a caller injects a larger ceiling (e.g. widget-level
      // override), validateText must agree so the UI counter and the
      // server-contract check stay in sync (SSOT).
      final String text = 'a' * 150;
      expect(
        CommentPostController.validateText(
          text: text,
          asOperator: true,
          maxLength: 200,
        ),
        isNull,
      );
    });

    test('honours injected maxLength when it is smaller than the default', () {
      // Conversely, a smaller injected limit must also take effect.
      final String text = 'a' * 40;
      expect(
        CommentPostController.validateText(
          text: text,
          asOperator: true,
          maxLength: 30,
        ),
        CommentValidationError.tooLong,
      );
    });
  });

  group('CommentPostController.computeVpos', () {
    test('returns 0 when beginAt is null', () {
      expect(
        CommentPostController.computeVpos(beginAt: null, now: DateTime.now()),
        0,
      );
    });

    test('computes 1/100-second offset from beginAt', () {
      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime now = begin.add(const Duration(milliseconds: 12345));
      // 12345 ms / 10 == 1234 (integer-truncated).
      expect(CommentPostController.computeVpos(beginAt: begin, now: now), 1234);
    });

    test('clamps to 0 when now is before beginAt', () {
      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime before = begin.subtract(const Duration(seconds: 5));
      expect(CommentPostController.computeVpos(beginAt: begin, now: before), 0);
    });

    test('vposBaseAt takes precedence over beginAt when both are set '
        '(Issue #465)', () {
      // Simulate the real-world gap: beginAt is the 開場時刻 and
      // vposBaseAt (= programSchedule.vposBaseTime) is the 配信開始時刻,
      // 30 seconds later. N Air's server-side ordering uses the
      // latter, so using beginAt would put this client's comments
      // 3000 vpos ahead of other viewers'.
      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime vposBase = begin.add(const Duration(seconds: 30));
      final DateTime now = begin.add(const Duration(seconds: 45));

      expect(
        CommentPostController.computeVpos(
          beginAt: begin,
          vposBaseAt: vposBase,
          now: now,
        ),
        1500, // (45s - 30s) = 15s = 1500 1/100-seconds
        reason:
            'when vposBaseAt is provided the reference must be vposBaseAt, '
            'not beginAt',
      );
    });

    test('falls back to beginAt when vposBaseAt is null (Issue #465 '
        'backward compat)', () {
      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime now = begin.add(const Duration(milliseconds: 5000));
      expect(
        CommentPostController.computeVpos(
          beginAt: begin,
          vposBaseAt: null,
          now: now,
        ),
        500,
      );
    });

    test('returns 0 when both references are null (Issue #465)', () {
      expect(
        CommentPostController.computeVpos(
          beginAt: null,
          vposBaseAt: null,
          now: DateTime.utc(2026, 1, 1, 10),
        ),
        0,
      );
    });

    test('clamps to 0 when now is before vposBaseAt (Issue #465)', () {
      final DateTime vposBase = DateTime.utc(2026, 1, 1, 10);
      final DateTime before = vposBase.subtract(const Duration(seconds: 5));
      // beginAt is earlier than `before` to confirm the clamp triggers
      // on vposBaseAt (the authoritative reference), not on beginAt.
      final DateTime begin = before.subtract(const Duration(seconds: 5));
      expect(
        CommentPostController.computeVpos(
          beginAt: begin,
          vposBaseAt: vposBase,
          now: before,
        ),
        0,
      );
    });
  });

  group('CommentPostController.ensureBroadcasterStatus', () {
    test('returns viewer when userSession is empty', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      final BroadcasterCheckOutcome result = await controller
          .ensureBroadcasterStatus(lv: 'lv123', userSession: '');

      expect(result, BroadcasterCheckOutcome.viewer);
      // No HTTP call should be made for empty session.
      expect(fake.requests, isEmpty);
    });

    test('returns unknown when lv is empty', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      final BroadcasterCheckOutcome result = await controller
          .ensureBroadcasterStatus(lv: '', userSession: 'session');

      expect(result, BroadcasterCheckOutcome.unknown);
    });

    test('returns broadcaster when own program matches current lv', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv345678901',
              'title': 'My Broadcast',
              'programProvider': <String, Object?>{'name': 'Me'},
            },
          ],
        },
      });

      final CommentPostController controller = _buildController(fake);

      final BroadcasterCheckOutcome result = await controller
          .ensureBroadcasterStatus(lv: 'lv345678901', userSession: 'session');

      expect(result, BroadcasterCheckOutcome.broadcaster);
    });

    test('returns viewer when own program differs from current lv', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv999999999',
              'title': 'Different broadcast',
              'programProvider': <String, Object?>{'name': 'Me'},
            },
          ],
        },
      });

      final CommentPostController controller = _buildController(fake);

      final BroadcasterCheckOutcome result = await controller
          .ensureBroadcasterStatus(lv: 'lv345678901', userSession: 'session');

      expect(result, BroadcasterCheckOutcome.viewer);
    });

    test('caches result for the same lv', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv345678901',
              'title': 'My Broadcast',
              'programProvider': <String, Object?>{'name': 'Me'},
            },
          ],
        },
      });
      final CommentPostController controller = _buildController(fake);

      await controller.ensureBroadcasterStatus(
        lv: 'lv345678901',
        userSession: 'session',
      );
      final int firstCount = fake.requests.length;

      await controller.ensureBroadcasterStatus(
        lv: 'lv345678901',
        userSession: 'session',
      );

      // Second call should not have issued a new request.
      expect(fake.requests.length, firstCount);
    });

    test('clearBroadcasterCache forces the next call to re-query', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv345678901',
              'title': 'My Broadcast',
              'programProvider': <String, Object?>{'name': 'Me'},
            },
          ],
        },
      });
      final CommentPostController controller = _buildController(fake);

      await controller.ensureBroadcasterStatus(
        lv: 'lv345678901',
        userSession: 'session',
      );
      final int firstCount = fake.requests.length;
      expect(firstCount, greaterThan(0));

      controller.clearBroadcasterCache();
      await controller.ensureBroadcasterStatus(
        lv: 'lv345678901',
        userSession: 'session',
      );

      // Cache invalidation must result in a fresh HTTP request even
      // though `lv` and `userSession` are unchanged. This is the
      // contract that lets `_startBroadcast` / `_endBroadcast` /
      // `_endBroadcastFromMenu` flip broadcaster-gated UI without
      // requiring a process restart (#752).
      expect(fake.requests.length, firstCount + 1);
    });
  });

  group('CommentPostController.postComment', () {
    test('returns validation error for empty text', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: '',
        asOperator: false,
      );

      expect(result.validationError, CommentValidationError.empty);
      expect(fake.requests, isEmpty);
    });

    test('returns invisibleOnly error for invisible-only text', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: '\u200B\u202E',
        asOperator: false,
      );

      expect(result.validationError, CommentValidationError.invisibleOnly);
      expect(fake.requests, isEmpty);
    });

    test('returns missingSession error when not logged in', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: '',
        text: 'hello',
        asOperator: false,
      );

      expect(result.validationError, CommentValidationError.missingSession);
      expect(fake.requests, isEmpty);
    });

    test(
      'returns tooLong error when text exceeds normal comment limit',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        final CommentPostController controller = _buildController(fake);

        final CommentSendResult result = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'a' * 76,
          asOperator: false,
        );

        expect(result.validationError, CommentValidationError.tooLong);
        expect(fake.requests, isEmpty);
      },
    );

    test('posts normal comment with computed vpos', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 200;
      fake.responseBody = '';
      final CommentPostController controller = _buildController(fake);

      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime now = begin.add(const Duration(seconds: 10));

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'hello',
        asOperator: false,
        beginAt: begin,
        now: now,
      );

      expect(result.isSuccess, isTrue);
      expect(fake.requests, hasLength(1));
      final _CapturedRequest request = fake.requests.last;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://live2.nicovideo.jp/unama/tool/v2/programs/lv1/comments',
      );
      expect(request.headers['x-frontend-id'], '134');
      expect(
        request.body,
        jsonEncode(<String, Object>{'text': 'hello', 'vpos': 1000}),
      );
    });

    test('posts operator comment via PUT when asOperator=true', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 200;
      fake.responseBody = '';
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'op',
        asOperator: true,
      );

      expect(result.isSuccess, isTrue);
      expect(fake.requests, hasLength(1));
      final _CapturedRequest request = fake.requests.last;
      expect(request.method, 'PUT');
      expect(
        request.uri.toString(),
        'https://live2.nicovideo.jp/watch/lv1/operator_comment',
      );
    });

    test('uses vpos=0 when beginAt is null', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 200;
      fake.responseBody = '';
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'hi',
        asOperator: false,
      );

      expect(result.isSuccess, isTrue);
      final _CapturedRequest request = fake.requests.last;
      expect(
        request.body,
        jsonEncode(<String, Object>{'text': 'hi', 'vpos': 0}),
      );
    });

    test('postComment forwards vposBaseAt so the server-bound vpos is '
        'computed against the authoritative reference, not beginAt '
        '(Issue #465)', () async {
      // Guards the integration between postComment and computeVpos.
      // Without this, a refactor could silently drop `vposBaseAt` from
      // the call inside postComment and the static computeVpos tests
      // would still pass.
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 200;
      fake.responseBody = '';
      final CommentPostController controller = _buildController(fake);

      final DateTime begin = DateTime.utc(2026, 1, 1, 10);
      final DateTime vposBase = begin.add(const Duration(seconds: 30));
      final DateTime now = begin.add(const Duration(seconds: 45));

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'hello',
        asOperator: false,
        beginAt: begin,
        vposBaseAt: vposBase,
        now: now,
      );

      expect(result.isSuccess, isTrue);
      final _CapturedRequest request = fake.requests.last;
      // vpos = (now - vposBaseAt) / 10ms = 15s / 10ms = 1500
      // (not 4500 which would be (now - beginAt) / 10ms)
      expect(
        request.body,
        jsonEncode(<String, Object>{'text': 'hello', 'vpos': 1500}),
      );
    });

    test(
      'postComment forwards injected maxLength into its validator (SSOT)',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        final CommentPostController controller = _buildController(fake);

        // 150-char operator comment would pass the default 100 ceiling
        // check against validateText(asOperator: true) and reach the
        // server — but because the caller supplies maxLength: 120 to
        // postComment, validation must reject it *before* the HTTP call.
        final CommentSendResult result = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'a' * 150,
          asOperator: true,
          maxLength: 120,
        );

        expect(result.validationError, CommentValidationError.tooLong);
        expect(
          fake.requests,
          isEmpty,
          reason: 'validator must run before any HTTP call',
        );
      },
    );

    test(
      'postComment forwards a larger maxLength and lets the post through',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        fake.responseStatusCode = 200;
        fake.responseBody = '';
        final CommentPostController controller = _buildController(fake);

        // 150-char text exceeds the default 100 operator ceiling, but the
        // caller-supplied maxLength: 200 allows it.
        final CommentSendResult result = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'a' * 150,
          asOperator: true,
          maxLength: 200,
        );

        expect(result.isSuccess, isTrue);
        expect(fake.requests, hasLength(1));
      },
    );

    test(
      'forwards isAnonymous=true to the normal-comment endpoint body',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        fake.responseStatusCode = 200;
        fake.responseBody = '';
        final CommentPostController controller = _buildController(fake);

        final CommentSendResult result = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'anon',
          asOperator: false,
          isAnonymous: true,
        );

        expect(result.isSuccess, isTrue);
        final _CapturedRequest request = fake.requests.single;
        final Map<String, Object?> decoded =
            jsonDecode(request.body!) as Map<String, Object?>;
        expect(decoded['isAnonymous'], isTrue);
      },
    );

    test(
      'omits isAnonymous from the body when the UI sends the default false',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        fake.responseStatusCode = 200;
        fake.responseBody = '';
        final CommentPostController controller = _buildController(fake);

        await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'normal',
          asOperator: false,
        );

        final _CapturedRequest request = fake.requests.single;
        expect(request.body, isNot(contains('isAnonymous')));
      },
    );

    test(
      'ignores isAnonymous for operator comments (operator body unaffected)',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        fake.responseStatusCode = 200;
        fake.responseBody = '';
        final CommentPostController controller = _buildController(fake);

        final CommentSendResult result = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'op',
          asOperator: true,
          isAnonymous: true,
        );

        expect(result.isSuccess, isTrue);
        final _CapturedRequest request = fake.requests.single;
        // Operator endpoint body must stay `{text, isPermCommand}` — never
        // isAnonymous.
        expect(request.body, isNot(contains('isAnonymous')));
        final Map<String, Object?> decoded =
            jsonDecode(request.body!) as Map<String, Object?>;
        expect(decoded.keys, containsAll(<String>['text', 'isPermCommand']));
      },
    );

    test('propagates server error from repository', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 403;
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{
          'errorCode': 'FORBIDDEN',
          'errorMessage': 'no',
        },
      });
      final CommentPostController controller = _buildController(fake);

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'hi',
        asOperator: true,
      );

      expect(result.isSuccess, isFalse);
      expect(result.postResult?.errorCode, 'FORBIDDEN');
    });

    test(
      'returns inFlight validation error when a send is already running',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        fake.responseStatusCode = 200;
        fake.responseBody = '';
        // Block the first send so the second one sees the in-flight state.
        fake.pendingCompleter = Completer<void>();
        final CommentPostController controller = _buildController(fake);

        final Future<CommentSendResult> first = controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'first',
          asOperator: false,
        );
        // Yield so the first send reaches the _isSending = true state.
        await Future<void>.delayed(Duration.zero);

        final CommentSendResult second = await controller.postComment(
          lv: 'lv1',
          userSession: 'session',
          text: 'second',
          asOperator: false,
        );

        expect(second.validationError, CommentValidationError.inFlight);

        // Release the first send.
        fake.pendingCompleter!.complete();
        final CommentSendResult firstResult = await first;
        expect(firstResult.isSuccess, isTrue);
      },
    );
  });

  group('CommentPostController.dispose', () {
    test('blocks further postComment calls after dispose', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseStatusCode = 200;
      fake.responseBody = '';
      final CommentPostController controller = _buildController(fake);

      controller.dispose();

      final CommentSendResult result = await controller.postComment(
        lv: 'lv1',
        userSession: 'session',
        text: 'hello',
        asOperator: false,
      );

      expect(result.validationError, CommentValidationError.missingProgram);
      expect(fake.requests, isEmpty);
    });

    test('dispose is idempotent', () {
      final _FakeHttpClient fake = _FakeHttpClient();
      final CommentPostController controller = _buildController(fake);

      // Must not throw on repeat calls — hot-reload and test teardown
      // routinely trigger multiple dispose() invocations.
      controller.dispose();
      expect(controller.dispose, returnsNormally);
      expect(controller.dispose, returnsNormally);
    });

    test(
      'blocks further ensureBroadcasterStatus calls after dispose',
      () async {
        final _FakeHttpClient fake = _FakeHttpClient();
        final CommentPostController controller = _buildController(fake);

        controller.dispose();

        final BroadcasterCheckOutcome outcome = await controller
            .ensureBroadcasterStatus(lv: 'lv1', userSession: 'session');

        expect(outcome, BroadcasterCheckOutcome.unknown);
      },
    );
  });

  group('CommentPostController.ensureBroadcasterStatus (session cache)', () {
    test('invalidates cache when userSession changes', () async {
      final _FakeHttpClient fake = _FakeHttpClient();
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv1',
              'title': 'Mine',
              'programProvider': <String, Object?>{'name': 'Me'},
            },
          ],
        },
      });
      final CommentPostController controller = _buildController(fake);

      await controller.ensureBroadcasterStatus(
        lv: 'lv1',
        userSession: 'user-a',
      );
      final int afterFirst = fake.requests.length;

      // Same lv but different session — must re-fetch instead of returning
      // stale cached "broadcaster" result for user-a.
      fake.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{'programs': <Object?>[]},
      });
      final BroadcasterCheckOutcome outcome = await controller
          .ensureBroadcasterStatus(lv: 'lv1', userSession: 'user-b');

      expect(outcome, BroadcasterCheckOutcome.viewer);
      expect(fake.requests.length, greaterThan(afterFirst));
    });
  });
}

CommentPostController _buildController(_FakeHttpClient http) {
  return CommentPostController(
    liveCommentRepository: LiveCommentRepository(httpClient: http),
    myProgramRepository: MyProgramRepository(httpClient: http),
  );
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  /// When set, each request's `close()` awaits this completer before
  /// returning a response — used to simulate an in-flight send.
  Completer<void>? pendingCompleter;

  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    return _FakeHttpClientRequest(uri: url, client: this, method: 'PUT');
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _FakeHttpClientRequest(uri: url, client: this, method: 'POST');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(uri: url, client: this, method: 'GET');
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
  _FakeHttpClientRequest({
    required this.uri,
    required this.client,
    required this.method,
  });

  @override
  final Uri uri;
  final _FakeHttpClient client;
  @override
  final String method;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  final StringBuffer _body = StringBuffer();

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? obj) {
    _body.write(obj);
  }

  @override
  Future<HttpClientResponse> close() async {
    final Map<String, String> headerMap = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        headerMap[key] = values.first;
      }
    });

    client.requests.add(
      _CapturedRequest(
        method: method,
        uri: uri,
        headers: headerMap,
        body: _body.isNotEmpty ? _body.toString() : null,
      ),
    );

    // Allow tests to block the response so they can observe in-flight state.
    final Completer<void>? gate = client.pendingCompleter;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }

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
  Future<E> drain<E>([E? futureValue]) {
    return listen(null).asFuture<E>(futureValue as E);
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
