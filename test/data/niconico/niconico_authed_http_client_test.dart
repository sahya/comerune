import 'dart:async';
import 'dart:io';

import 'package:comerune/data/niconico/niconico_authed_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal concrete subclass for testing the abstract base class.
///
/// Re-exposes the `@protected` fields and methods through public getters /
/// pass-through methods so the test can assert against them without ignoring
/// analyzer hints at every call site.
class _TestClient extends NiconicoAuthedHttpClient {
  _TestClient({
    HttpClient? httpClient,
    String userAgent = NiconicoAuthedHttpClient.defaultUserAgent,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : super(
         httpClient: httpClient,
         userAgent: userAgent,
         requestTimeout: requestTimeout,
       );

  String get exposedUserAgent => userAgent;
  Duration get exposedRequestTimeout => requestTimeout;

  // Protected method pass-throughs for tests.
  void publicSetAuthHeaders(HttpClientRequest request, String userSession) =>
      setAuthHeaders(request, userSession);

  NiconicoErrorFields publicParseErrorBody(
    String body,
    int statusCode,
    String operationName,
    String logName,
  ) => parseErrorBody(body, statusCode, operationName, logName);

  String publicHttpStatusToErrorCode(int statusCode) =>
      httpStatusToErrorCode(statusCode);

  String publicHandleTimeout(
    HttpClientRequest? request,
    TimeoutException e,
    String operationName,
    String logName,
  ) => handleTimeout(request, e, operationName, logName);

  String publicHandleException(
    Exception e,
    String operationName,
    String logName,
  ) => handleException(e, operationName, logName);

  NiconicoInputValidationStatus publicValidateCallInputs({
    required String programId,
    required String userSession,
    required String logName,
  }) => validateCallInputs(
    programId: programId,
    userSession: userSession,
    logName: logName,
  );
}

void main() {
  group('NiconicoAuthedHttpClient', () {
    group('setAuthHeaders', () {
      test('sets all required authentication and content headers', () {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final _TestClient client = _TestClient(httpClient: httpClient);

        final _FakeHttpClientRequest request = _FakeHttpClientRequest();
        client.publicSetAuthHeaders(request, 'my_session_token');

        final Map<String, String> headers = request.capturedHeaders;
        expect(headers['Cookie'], 'user_session=my_session_token');
        expect(headers['X-Niconico-Session'], 'my_session_token');
        expect(
          headers['User-Agent'],
          NiconicoAuthedHttpClient.defaultUserAgent,
        );
        expect(headers['Content-Type'], 'application/json');
        expect(headers['Accept'], 'application/json');

        client.dispose();
      });

      test('uses custom user agent when provided', () {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final _TestClient client = _TestClient(
          httpClient: httpClient,
          userAgent: 'CustomAgent/1.0',
        );

        final _FakeHttpClientRequest request = _FakeHttpClientRequest();
        client.publicSetAuthHeaders(request, 'session');

        expect(request.capturedHeaders['User-Agent'], 'CustomAgent/1.0');

        client.dispose();
      });
    });

    group('parseErrorBody', () {
      test('extracts errorCode and errorMessage from meta', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '{"meta":{"errorCode":"FORBIDDEN","errorMessage":"not allowed"}}',
          403,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'FORBIDDEN');
        expect(result.errorMessage, 'not allowed');

        client.dispose();
      });

      test('falls back to data.message when meta.errorMessage is absent', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '{"meta":{"errorCode":"BAD_REQUEST"},'
              '"data":{"message":"invalid input"}}',
          400,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'BAD_REQUEST');
        expect(result.errorMessage, 'invalid input');

        client.dispose();
      });

      test('prefers meta.errorMessage over data.message', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '{"meta":{"errorCode":"X","errorMessage":"from meta"},'
              '"data":{"message":"from data"}}',
          400,
          'testOp',
          'TestRepo',
        );

        expect(result.errorMessage, 'from meta');

        client.dispose();
      });

      test('maps HTTP status code when meta.errorCode is absent', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '{"meta":{"status":401}}',
          401,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'UNAUTHORIZED');
        expect(result.errorMessage, isNull);

        client.dispose();
      });

      test('handles non-JSON error body gracefully', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          'Internal Server Error',
          500,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'HTTP_500');
        expect(result.errorMessage, isNull);

        client.dispose();
      });

      test('handles empty body', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '',
          404,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'NOT_FOUND');
        expect(result.errorMessage, isNull);

        client.dispose();
      });

      test('handles JSON without meta or data fields', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '{"other":"value"}',
          403,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'FORBIDDEN');
        expect(result.errorMessage, isNull);

        client.dispose();
      });

      test('handles JSON array body', () {
        final _TestClient client = _TestClient();

        final NiconicoErrorFields result = client.publicParseErrorBody(
          '[1, 2, 3]',
          500,
          'testOp',
          'TestRepo',
        );

        expect(result.errorCode, 'HTTP_500');
        expect(result.errorMessage, isNull);

        client.dispose();
      });
    });

    group('httpStatusToErrorCode', () {
      test('maps 400 to BAD_REQUEST', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(400), 'BAD_REQUEST');
        client.dispose();
      });

      test('maps 401 to UNAUTHORIZED', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(401), 'UNAUTHORIZED');
        client.dispose();
      });

      test('maps 403 to FORBIDDEN', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(403), 'FORBIDDEN');
        client.dispose();
      });

      test('maps 404 to NOT_FOUND', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(404), 'NOT_FOUND');
        client.dispose();
      });

      test('maps 409 to CONFLICT', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(409), 'CONFLICT');
        client.dispose();
      });

      test('maps unknown status to HTTP_<code>', () {
        final _TestClient client = _TestClient();
        expect(client.publicHttpStatusToErrorCode(503), 'HTTP_503');
        expect(client.publicHttpStatusToErrorCode(502), 'HTTP_502');
        client.dispose();
      });
    });

    group('handleTimeout', () {
      test('aborts the request and returns timeout message', () {
        final _TestClient client = _TestClient();
        final _FakeHttpClientRequest request = _FakeHttpClientRequest();

        final String message = client.publicHandleTimeout(
          request,
          TimeoutException('test', const Duration(seconds: 5)),
          'myOp',
          'TestRepo',
        );

        expect(request.isAborted, isTrue);
        expect(message, contains('TimeoutException'));
        expect(message, contains('0:00:05'));

        client.dispose();
      });

      test('tolerates null request', () {
        final _TestClient client = _TestClient();

        final String message = client.publicHandleTimeout(
          null,
          TimeoutException('test'),
          'myOp',
          'TestRepo',
        );

        expect(message, contains('TimeoutException'));

        client.dispose();
      });
    });

    group('handleException', () {
      test('returns runtime type as error message', () {
        final _TestClient client = _TestClient();

        final String message = client.publicHandleException(
          const SocketException('connection refused'),
          'myOp',
          'TestRepo',
        );

        expect(message, 'SocketException');

        client.dispose();
      });
    });

    group('dispose', () {
      test('closes the underlying HttpClient', () {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final _TestClient client = _TestClient(httpClient: httpClient);

        expect(httpClient.isClosed, isFalse);
        client.dispose();
        expect(httpClient.isClosed, isTrue);
      });
    });

    group('isValidAuthHeaderValue', () {
      test('accepts a normal URL-safe session token', () {
        expect(
          NiconicoAuthedHttpClient.isValidAuthHeaderValue('abc123_=-xyz'),
          isTrue,
        );
      });

      test('accepts an empty string (emptiness is caller concern)', () {
        // Empty-string check is the caller's responsibility; this validator
        // only rejects the three header-splitting control characters.
        expect(NiconicoAuthedHttpClient.isValidAuthHeaderValue(''), isTrue);
      });

      test('rejects a value containing CR (0x0D)', () {
        expect(
          NiconicoAuthedHttpClient.isValidAuthHeaderValue('valid\r'),
          isFalse,
        );
      });

      test('rejects a value containing LF (0x0A)', () {
        expect(
          NiconicoAuthedHttpClient.isValidAuthHeaderValue('valid\nfoo'),
          isFalse,
        );
      });

      test('rejects a value containing CRLF (classic injection)', () {
        expect(
          NiconicoAuthedHttpClient.isValidAuthHeaderValue(
            'valid\r\nX-Injected: 1',
          ),
          isFalse,
        );
      });

      test('rejects a value containing NUL (0x00)', () {
        expect(
          NiconicoAuthedHttpClient.isValidAuthHeaderValue('bad\u0000byte'),
          isFalse,
        );
      });

      test('rejects mid-string injection variants', () {
        for (final String poison in <String>[
          'a\rb',
          'a\nb',
          'a\u0000b',
          '\r',
          '\n',
          '\u0000',
          '\r\n',
        ]) {
          expect(
            NiconicoAuthedHttpClient.isValidAuthHeaderValue(poison),
            isFalse,
            reason:
                'expected rejection for code units '
                '${poison.codeUnits.map((int c) => '0x${c.toRadixString(16)}').toList()}',
          );
        }
      });
    });

    group('isValidLv', () {
      test('accepts well-formed lv ids', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv123'), isTrue);
        expect(NiconicoAuthedHttpClient.isValidLv('lv345678901'), isTrue);
        expect(NiconicoAuthedHttpClient.isValidLv('lv0'), isTrue);
      });

      test('rejects a bare "lv" prefix with no digits', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv'), isFalse);
      });

      test('rejects empty string', () {
        expect(NiconicoAuthedHttpClient.isValidLv(''), isFalse);
      });

      test('rejects non-digit trailing characters', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv1a'), isFalse);
        expect(NiconicoAuthedHttpClient.isValidLv('lv-123'), isFalse);
        expect(NiconicoAuthedHttpClient.isValidLv('lv 123'), isFalse);
      });

      test('rejects path-injection attempts', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv123/../admin'), isFalse);
      });

      test('rejects query / fragment splitters', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv123?foo=bar'), isFalse);
        expect(NiconicoAuthedHttpClient.isValidLv('lv123#frag'), isFalse);
      });

      test('rejects uppercase LV prefix', () {
        expect(NiconicoAuthedHttpClient.isValidLv('LV123'), isFalse);
      });

      test('rejects pure numeric string without lv prefix', () {
        expect(NiconicoAuthedHttpClient.isValidLv('123'), isFalse);
      });

      test('rejects full-width digits', () {
        expect(NiconicoAuthedHttpClient.isValidLv('lv１２３'), isFalse);
      });
    });

    group('validateCallInputs', () {
      test('returns ok for well-formed inputs', () {
        final _TestClient client = _TestClient();
        expect(
          client.publicValidateCallInputs(
            programId: 'lv123',
            userSession: 'abc_session',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.ok,
        );
        client.dispose();
      });

      test('returns empty when programId is empty', () {
        final _TestClient client = _TestClient();
        expect(
          client.publicValidateCallInputs(
            programId: '',
            userSession: 'abc_session',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.empty,
        );
        client.dispose();
      });

      test('returns empty when userSession is empty or whitespace-only', () {
        final _TestClient client = _TestClient();
        expect(
          client.publicValidateCallInputs(
            programId: 'lv123',
            userSession: '',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.empty,
        );
        expect(
          client.publicValidateCallInputs(
            programId: 'lv123',
            userSession: '   ',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.empty,
          reason: 'whitespace-only session must be treated as empty',
        );
        client.dispose();
      });

      test('returns malformed when userSession carries CR / LF / NUL', () {
        final _TestClient client = _TestClient();
        for (final String poison in <String>[
          'valid\r\nX-Injected: 1',
          'valid\nfoo',
          'valid\r',
          'bad\u0000byte',
        ]) {
          expect(
            client.publicValidateCallInputs(
              programId: 'lv123',
              userSession: poison,
              logName: 'Test',
            ),
            NiconicoInputValidationStatus.malformed,
            reason:
                'poisoned session: '
                '${poison.codeUnits.map((int c) => '0x${c.toRadixString(16)}').toList()}',
          );
        }
        client.dispose();
      });

      test('returns malformed when programId violates lv format', () {
        final _TestClient client = _TestClient();
        for (final String bad in <String>[
          'lv',
          'lv1a',
          'lv123/../admin',
          '123',
          'LV123',
          'lv 123',
          'lv-123',
          'lv123?foo=bar',
          'lv123#frag',
          'lv１２３',
        ]) {
          expect(
            client.publicValidateCallInputs(
              programId: bad,
              userSession: 'valid_session',
              logName: 'Test',
            ),
            NiconicoInputValidationStatus.malformed,
            reason: 'malformed lv: <$bad>',
          );
        }
        client.dispose();
      });

      test('emptiness check takes priority over malformed check so callers can '
          'report the more specific "required" message', () {
        final _TestClient client = _TestClient();
        // programId is empty AND userSession is structurally bad. Empty
        // check runs first, so the outcome is `empty` not `malformed`.
        expect(
          client.publicValidateCallInputs(
            programId: '',
            userSession: 'bad\rsession',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.empty,
        );
        // Symmetric case: malformed programId AND empty userSession —
        // still `empty` because the combined emptiness check fires first.
        expect(
          client.publicValidateCallInputs(
            programId: 'lv123/../admin',
            userSession: '',
            logName: 'Test',
          ),
          NiconicoInputValidationStatus.empty,
        );
        client.dispose();
      });
    });

    group('constructor defaults', () {
      test('sets connection timeout to 10 seconds', () {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        _TestClient(httpClient: httpClient);

        expect(httpClient.connectionTimeoutValue, const Duration(seconds: 10));
      });

      test('exposes requestTimeout to subclasses', () {
        final _TestClient client = _TestClient(
          requestTimeout: const Duration(seconds: 30),
        );

        expect(client.exposedRequestTimeout, const Duration(seconds: 30));

        client.dispose();
      });

      test('uses default user agent when none provided', () {
        final _TestClient client = _TestClient();
        expect(
          client.exposedUserAgent,
          NiconicoAuthedHttpClient.defaultUserAgent,
        );
        client.dispose();
      });
    });
  });
}

class _FakeHttpClient implements HttpClient {
  bool isClosed = false;
  Duration? connectionTimeoutValue;

  @override
  set connectionTimeout(Duration? timeout) {
    connectionTimeoutValue = timeout;
  }

  @override
  void close({bool force = false}) {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  bool isAborted = false;

  Map<String, String> get capturedHeaders {
    final Map<String, String> result = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        result[key] = values.first;
      }
    });
    return result;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    isAborted = true;
  }

  @override
  HttpHeaders get headers => _headers;

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
