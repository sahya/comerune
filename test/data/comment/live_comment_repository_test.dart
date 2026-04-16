import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/comment/live_comment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveCommentRepository', () {
    group('postOperatorComment', () {
      test(
        'sends PUT with text and isPermCommand=false, returns success',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseBody = '';
          httpClient.responseStatusCode = 200;

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'こんにちは',
          );

          expect(result.success, isTrue);

          expect(httpClient.requests, hasLength(1));
          final _CapturedRequest request = httpClient.requests[0];
          expect(request.method, 'PUT');
          expect(
            request.uri.toString(),
            'https://live2.nicovideo.jp/watch/lv345678901/operator_comment',
          );
          expect(request.headers['Cookie'], 'user_session=test_session');
          expect(request.headers['X-Niconico-Session'], 'test_session');
          expect(request.headers['Content-Type'], 'application/json');
          // Operator endpoint must NOT send the x-frontend-id header (that is a
          // normal-comment-only header).
          expect(request.headers['x-frontend-id'], isNull);
          expect(
            request.body,
            jsonEncode(<String, Object>{
              'text': 'こんにちは',
              'isPermCommand': false,
            }),
          );

          repository.dispose();
        },
      );

      test('handles HTTP 204 (empty body) as success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 204;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isTrue);

        repository.dispose();
      });

      test('returns FORBIDDEN on HTTP 403 with errorCode in meta', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 403;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{
            'status': 403,
            'errorCode': 'FORBIDDEN',
            'errorMessage': 'not a broadcaster',
          },
        });

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'FORBIDDEN');
        expect(result.errorMessage, 'not a broadcaster');

        repository.dispose();
      });

      test(
        'maps HTTP 401 to UNAUTHORIZED when body has no errorCode',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseStatusCode = 401;
          httpClient.responseBody = '';

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'hi',
          );

          expect(result.success, isFalse);
          expect(result.errorCode, 'UNAUTHORIZED');

          repository.dispose();
        },
      );

      test('returns INVALID_PARAMS when programId is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: '',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns INVALID_PARAMS when userSession is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: '',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns NETWORK_ERROR on exception', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.shouldThrowOnRequest = true;

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');

        repository.dispose();
      });
    });

    group('postNormalComment', () {
      test('sends POST with text/vpos and x-frontend-id=134 header', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        });

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: '88888',
          vpos: 12345,
        );

        expect(result.success, isTrue);

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        expect(request.method, 'POST');
        expect(
          request.uri.toString(),
          'https://live2.nicovideo.jp/unama/tool/v2/programs/lv345678901/comments',
        );
        expect(request.headers['Cookie'], 'user_session=test_session');
        expect(request.headers['X-Niconico-Session'], 'test_session');
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.headers['x-frontend-id'], '134');
        expect(
          request.body,
          jsonEncode(<String, Object>{'text': '88888', 'vpos': 12345}),
        );

        repository.dispose();
      });

      test('returns BAD_REQUEST on HTTP 400', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 400;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 400},
          'data': <String, Object?>{'message': 'invalid text'},
        });

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'bad',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'BAD_REQUEST');
        expect(result.errorMessage, 'invalid text');

        repository.dispose();
      });

      test('maps HTTP 409 to CONFLICT', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 409;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'CONFLICT');

        repository.dispose();
      });

      test('maps unknown 5xx to HTTP_<code>', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 503;
        httpClient.responseBody = 'temporarily unavailable';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'HTTP_503');

        repository.dispose();
      });

      test('returns INVALID_PARAMS when programId is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: '',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns INVALID_PARAMS when userSession is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: '',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns NETWORK_ERROR on exception', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.shouldThrowOnRequest = true;

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');

        repository.dispose();
      });

      test('omits isAnonymous from body when isAnonymous defaults to false '
          '(byte-compat with pre-toggle callers)', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        final _CapturedRequest request = httpClient.requests.single;
        // Must match the pre-toggle body exactly so that existing call
        // sites retain identical wire output.
        expect(
          request.body,
          jsonEncode(<String, Object>{'text': 'hi', 'vpos': 0}),
        );
        expect(request.body, isNot(contains('isAnonymous')));

        repository.dispose();
      });

      test(
        'omits isAnonymous from body when isAnonymous=false is explicit',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = '';

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          await repository.postNormalComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'hi',
            vpos: 7,
            isAnonymous: false,
          );

          final _CapturedRequest request = httpClient.requests.single;
          expect(
            request.body,
            jsonEncode(<String, Object>{'text': 'hi', 'vpos': 7}),
          );
          expect(request.body, isNot(contains('isAnonymous')));

          repository.dispose();
        },
      );

      test('includes top-level isAnonymous=true when isAnonymous=true '
          '(candidate B shape)', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: '匿名テスト',
          vpos: 99,
          isAnonymous: true,
        );
        expect(result.success, isTrue);

        final _CapturedRequest request = httpClient.requests.single;
        // The current implementation adopts candidate B (top-level flag),
        // matching Hakumai / nicolivehelperxx. Assert the exact shape so
        // a future regression to nested `modifier.isAnonymous` is caught.
        final Map<String, Object?> decoded =
            jsonDecode(request.body!) as Map<String, Object?>;
        expect(decoded['text'], '匿名テスト');
        expect(decoded['vpos'], 99);
        expect(decoded['isAnonymous'], isTrue);
        expect(
          decoded.containsKey('modifier'),
          isFalse,
          reason:
              'candidate B shape does not include a modifier object; '
              'if the live-server trial proves candidate A is needed, '
              'this assertion and the body builder must be updated '
              'together.',
        );

        repository.dispose();
      });

      test('maps HTTP 429 to RATE_LIMITED', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 429;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'spam',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'RATE_LIMITED');

        repository.dispose();
      });
    });

    group('defensive input validation', () {
      test(
        'rejects user_session containing CR / LF / NUL (header injection)',
        () async {
          for (final String poison in <String>[
            'valid\r\nX-Injected: 1',
            'valid\nfoo',
            'valid\r',
            'bad\u0000byte',
          ]) {
            final _FakeHttpClient httpClient = _FakeHttpClient();
            final LiveCommentRepository repository = LiveCommentRepository(
              httpClient: httpClient,
            );

            final String caseLabel =
                'poisoned session: '
                '${poison.codeUnits.map((int c) => '0x${c.toRadixString(16)}').toList()}';

            final CommentPostResult opResult = await repository
                .postOperatorComment(
                  programId: 'lv123',
                  userSession: poison,
                  text: 'hi',
                );
            expect(opResult.success, isFalse, reason: caseLabel);
            expect(opResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

            final CommentPostResult normalResult = await repository
                .postNormalComment(
                  programId: 'lv123',
                  userSession: poison,
                  text: 'hi',
                  vpos: 0,
                );
            expect(normalResult.success, isFalse, reason: caseLabel);
            expect(normalResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

            // No HTTP request should reach the fake client.
            expect(httpClient.requests, isEmpty, reason: caseLabel);

            repository.dispose();
          }
        },
      );

      test('rejects malformed programId values (path injection)', () async {
        for (final String malformed in <String>[
          'lv',
          'lv1a',
          'lv123/../admin',
          '123',
          'LV123',
          'lv 123',
          'lv-123',
          // Security-audit additions: query / fragment splitters and
          // full-width decimal digits must also be rejected per the
          // `_isValidLv` docstring contract.
          'lv123?foo=bar',
          'lv123#frag',
          'lv１２３',
        ]) {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final String caseLabel = 'malformed lv: <$malformed>';

          final CommentPostResult opResult = await repository
              .postOperatorComment(
                programId: malformed,
                userSession: 'valid_session',
                text: 'hi',
              );
          expect(opResult.success, isFalse, reason: caseLabel);
          expect(opResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

          final CommentPostResult normalResult = await repository
              .postNormalComment(
                programId: malformed,
                userSession: 'valid_session',
                text: 'hi',
                vpos: 0,
              );
          expect(normalResult.success, isFalse, reason: caseLabel);
          expect(normalResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

          expect(httpClient.requests, isEmpty, reason: caseLabel);

          repository.dispose();
        }
      });

      test('accepts normal well-formed programId', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'session',
          text: 'hi',
        );
        expect(result.success, isTrue);

        repository.dispose();
      });
    });

    group('HTTP 200 + meta body error (false-success protection)', () {
      test('treats HTTP 200 with meta.status != 200 as failure', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{
            'status': 400,
            'errorCode': 'COMMENT_LOCKED',
            'errorMessage': 'Comments are disabled',
          },
        });

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postNormalComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'hi',
          vpos: 0,
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'COMMENT_LOCKED');
        expect(result.errorMessage, 'Comments are disabled');

        repository.dispose();
      });

      test(
        'treats HTTP 200 with meta.status=200 and errorCode=OK as success',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = jsonEncode(<String, Object?>{
            'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          });

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'ok',
          );

          expect(result.success, isTrue);

          repository.dispose();
        },
      );

      test(
        'treats HTTP 200 with empty body as success (no meta to parse)',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = '';

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'ok',
          );

          expect(result.success, isTrue);

          repository.dispose();
        },
      );

      test('treats HTTP 200 with non-JSON body as success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = 'OK';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'ok',
        );

        expect(result.success, isTrue);

        repository.dispose();
      });

      test(
        'treats HTTP 200 with meta error on operator endpoint as failure',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = jsonEncode(<String, Object?>{
            'meta': <String, Object?>{
              'status': 429,
              'errorCode': 'RATE_LIMITED',
              'errorMessage': 'Too fast',
            },
          });

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'fast',
          );

          expect(result.success, isFalse);
          expect(result.errorCode, 'RATE_LIMITED');
          expect(result.errorMessage, 'Too fast');

          repository.dispose();
        },
      );

      test('sends Accept: application/json header', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        await repository.postOperatorComment(
          programId: 'lv1',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(
          httpClient.requests.single.headers['Accept'],
          'application/json',
        );

        repository.dispose();
      });

      test('returns NETWORK_ERROR and aborts the request when the response '
          'stalls beyond timeout', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.pendingCompleter = Completer<void>();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
          requestTimeout: const Duration(milliseconds: 50),
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv1',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');
        expect(httpClient.requests.single.request.isAborted, isTrue);

        // Release the stalled response so the fake HttpClient can shut down.
        httpClient.pendingCompleter!.complete();
        repository.dispose();
      });

      test(
        'aborts the request on timeout for postNormalComment as well',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.pendingCompleter = Completer<void>();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = '';

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
            requestTimeout: const Duration(milliseconds: 50),
          );

          final CommentPostResult result = await repository.postNormalComment(
            programId: 'lv345678901',
            userSession: 'test_session',
            text: 'hi',
            vpos: 0,
          );

          expect(result.success, isFalse);
          expect(result.errorCode, 'NETWORK_ERROR');
          expect(httpClient.requests.single.request.isAborted, isTrue);

          httpClient.pendingCompleter!.complete();
          repository.dispose();
        },
      );

      test(
        'aborts the request when the response body stalls beyond timeout',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.bodyStallCompleter = Completer<void>();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = '';

          final LiveCommentRepository repository = LiveCommentRepository(
            httpClient: httpClient,
            requestTimeout: const Duration(milliseconds: 50),
          );

          final CommentPostResult result = await repository.postOperatorComment(
            programId: 'lv1',
            userSession: 'test_session',
            text: 'hi',
          );

          expect(result.success, isFalse);
          expect(result.errorCode, 'NETWORK_ERROR');
          expect(result.errorMessage, contains('TimeoutException'));
          expect(result.errorMessage, contains('0:00:00.050'));
          expect(httpClient.requests.single.request.isAborted, isTrue);

          httpClient.bodyStallCompleter!.complete();
          repository.dispose();
        },
      );

      test('does NOT abort the request for non-timeout exceptions', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 500;
        httpClient.responseBody = 'boom';

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
          requestTimeout: const Duration(milliseconds: 50),
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv1',
          userSession: 'test_session',
          text: 'hi',
        );

        expect(result.success, isFalse);
        expect(
          httpClient.requests.single.request.isAborted,
          isFalse,
          reason: 'abort() should only be called on timeout, not HTTP errors',
        );

        repository.dispose();
      });

      test('accepts meta.status as a string "200" plus errorCode OK', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': '200', 'errorCode': 'OK'},
        });

        final LiveCommentRepository repository = LiveCommentRepository(
          httpClient: httpClient,
        );

        final CommentPostResult result = await repository.postOperatorComment(
          programId: 'lv345678901',
          userSession: 'test_session',
          text: 'ok',
        );

        expect(result.success, isTrue);

        repository.dispose();
      });
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.request,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final _FakeHttpClientRequest request;
  final String? body;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  bool shouldThrowOnRequest = false;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  /// When set, each request's `close()` awaits this completer before
  /// returning a response — used to simulate a stalled server for timeout
  /// coverage.
  Completer<void>? pendingCompleter;

  /// When set, the response body stream awaits this completer before
  /// emitting data — used to simulate a stalled response body for timeout
  /// coverage.
  Completer<void>? bodyStallCompleter;

  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this, method: 'PUT');
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this, method: 'POST');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
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

  bool isAborted = false;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    isAborted = true;
  }

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
        request: this,
        body: _body.isNotEmpty ? _body.toString() : null,
      ),
    );

    final Completer<void>? gate = client.pendingCompleter;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }

    return _FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
      bodyStallCompleter: client.bodyStallCompleter,
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
  _FakeHttpClientResponse({
    required this.statusCode,
    required String body,
    this.bodyStallCompleter,
  }) : _body = body;

  @override
  final int statusCode;
  final String _body;
  final Completer<void>? bodyStallCompleter;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final Completer<void>? stall = bodyStallCompleter;
    if (stall != null && !stall.isCompleted) {
      // Simulate a response whose body never arrives until the completer
      // fires — used to test body-read timeout.
      final Stream<List<int>> delayed = stall.future
          .then<List<int>>((_) => utf8.encode(_body))
          .asStream();
      return delayed.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
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
