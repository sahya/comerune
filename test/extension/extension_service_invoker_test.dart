import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_result.dart';
import 'package:comerune/extension/extension_service_invoker.dart';
import 'package:comerune/extension/service_override_policy.dart';

abstract class _TestService {
  Future<ExtensionResult<String>> hello();
}

class _OkExtension implements _TestService {
  const _OkExtension(this._label);
  final String _label;

  @override
  Future<ExtensionResult<String>> hello() async {
    return ExtensionResultOk<String>('ext:$_label');
  }
}

class _UnsupportedExtension implements _TestService {
  const _UnsupportedExtension();

  @override
  Future<ExtensionResult<String>> hello() async {
    return const ExtensionResultUnsupported<String>();
  }
}

class _ThrowingExtension implements _TestService {
  const _ThrowingExtension();

  @override
  Future<ExtensionResult<String>> hello() async {
    throw const _ExtensionBoom();
  }
}

class _ExtensionBoom implements Exception {
  const _ExtensionBoom();
  @override
  String toString() => 'ExtensionBoom';
}

class _HostBoom implements Exception {
  const _HostBoom();
  @override
  String toString() => 'HostBoom';
}

ExtensionRegistry _registryWith(_TestService? service) {
  final ExtensionRegistry registry = ExtensionRegistry();
  if (service != null) {
    registry.registerService<_TestService>(service);
  }
  return registry;
}

Future<ExtensionResult<String>> _callExt(_TestService s) => s.hello();

void main() {
  group(
    'ExtensionServiceInvoker.invoke — extensionFirstFallback (default)',
    () {
      test('extension Ok wins; host fallback never runs', () async {
        bool hostRan = false;
        final ExtensionRegistry registry = _registryWith(
          const _OkExtension('first'),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async {
                hostRan = true;
                return const ExtensionResultOk<String>('host');
              },
            );

        expect(result, equals(const ExtensionResultOk<String>('ext:first')));
        expect(hostRan, isFalse);
      });

      test('extension Unsupported falls back to host', () async {
        final ExtensionRegistry registry = _registryWith(
          const _UnsupportedExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async => const ExtensionResultOk<String>('host'),
            );

        expect(result, equals(const ExtensionResultOk<String>('host')));
      });

      test('extension Failure falls back to host', () async {
        final ExtensionRegistry registry = _registryWith(
          const _ThrowingExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async => const ExtensionResultOk<String>('host'),
            );

        expect(result, equals(const ExtensionResultOk<String>('host')));
      });

      test('no extension registered: host runs', () async {
        final ExtensionRegistry registry = _registryWith(null);

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async => const ExtensionResultOk<String>('host'),
            );

        expect(result, equals(const ExtensionResultOk<String>('host')));
      });

      test('no extension and no host: Unsupported', () async {
        final ExtensionRegistry registry = _registryWith(null);

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
            );

        expect(result, isA<ExtensionResultUnsupported<String>>());
      });
    },
  );

  group('ExtensionServiceInvoker.invoke — hostOnly', () {
    test('extension is ignored even when present', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('ignored'),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async => const ExtensionResultOk<String>('host'),
            policy: ServiceOverridePolicy.hostOnly,
          );

      expect(result, equals(const ExtensionResultOk<String>('host')));
    });

    test('no host fallback yields Unsupported', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('ignored'),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            policy: ServiceOverridePolicy.hostOnly,
          );

      expect(result, isA<ExtensionResultUnsupported<String>>());
    });
  });

  group('ExtensionServiceInvoker.invoke — hostFirstFallback', () {
    test('host Ok wins; extension never runs', () async {
      bool extensionRan = false;
      final ExtensionRegistry registry = _registryWith(
        _CountingExtension(() => extensionRan = true),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async => const ExtensionResultOk<String>('host'),
            policy: ServiceOverridePolicy.hostFirstFallback,
          );

      expect(result, equals(const ExtensionResultOk<String>('host')));
      expect(extensionRan, isFalse);
    });

    test('host Unsupported falls back to extension', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('ext'),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async =>
                const ExtensionResultUnsupported<String>(),
            policy: ServiceOverridePolicy.hostFirstFallback,
          );

      expect(result, equals(const ExtensionResultOk<String>('ext:ext')));
    });

    test('no host: extension runs (when present)', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('ext'),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            policy: ServiceOverridePolicy.hostFirstFallback,
          );

      expect(result, equals(const ExtensionResultOk<String>('ext:ext')));
    });

    test('no host and no extension: Unsupported', () async {
      final ExtensionRegistry registry = _registryWith(null);

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            policy: ServiceOverridePolicy.hostFirstFallback,
          );

      expect(result, isA<ExtensionResultUnsupported<String>>());
    });

    test('host throws is NOT caught (bugs surface)', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('ignored'),
      );

      await expectLater(
        ExtensionServiceInvoker.invoke<_TestService, String>(
          registry,
          callExtension: _callExt,
          hostFallback: () async => throw const _HostBoom(),
          policy: ServiceOverridePolicy.hostFirstFallback,
        ),
        throwsA(isA<_HostBoom>()),
      );
    });

    test(
      'host Unsupported + extension throws: extension Failure surfaces',
      () async {
        final ExtensionRegistry registry = _registryWith(
          const _ThrowingExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async =>
                  const ExtensionResultUnsupported<String>(),
              policy: ServiceOverridePolicy.hostFirstFallback,
            );

        expect(result, isA<ExtensionResultFailure<String>>());
      },
    );
  });

  group('ExtensionServiceInvoker.invoke — extensionOnly', () {
    test('extension Ok wins', () async {
      final ExtensionRegistry registry = _registryWith(
        const _OkExtension('only'),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async => const ExtensionResultOk<String>('host'),
            policy: ServiceOverridePolicy.extensionOnly,
          );

      expect(result, equals(const ExtensionResultOk<String>('ext:only')));
    });

    test('no extension: Unsupported even when host fallback exists', () async {
      bool hostRan = false;
      final ExtensionRegistry registry = _registryWith(null);

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async {
              hostRan = true;
              return const ExtensionResultOk<String>('host');
            },
            policy: ServiceOverridePolicy.extensionOnly,
          );

      expect(result, isA<ExtensionResultUnsupported<String>>());
      expect(hostRan, isFalse);
    });

    test('extension throw becomes Failure', () async {
      final ExtensionRegistry registry = _registryWith(
        const _ThrowingExtension(),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            policy: ServiceOverridePolicy.extensionOnly,
          );

      expect(result, isA<ExtensionResultFailure<String>>());
      expect(
        (result as ExtensionResultFailure<String>).cause,
        isA<_ExtensionBoom>(),
      );
    });
  });

  group('ExtensionServiceInvoker — exception boundary', () {
    test(
      'extension throws + no host: original Failure is preserved (not flattened to Unsupported)',
      () async {
        final ExtensionRegistry registry = _registryWith(
          const _ThrowingExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
            );

        expect(result, isA<ExtensionResultFailure<String>>());
        expect(
          (result as ExtensionResultFailure<String>).cause,
          isA<_ExtensionBoom>(),
        );
      },
    );

    test(
      'extension throws + host returns Unsupported: extension Failure preserved',
      () async {
        final ExtensionRegistry registry = _registryWith(
          const _ThrowingExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async =>
                  const ExtensionResultUnsupported<String>(),
            );

        // Both sides could not produce Ok; surface the Failure since
        // it carries the most actionable diagnostic for the caller.
        expect(result, isA<ExtensionResultFailure<String>>());
      },
    );

    test(
      'extension Unsupported + host Unsupported: surfaces Unsupported',
      () async {
        final ExtensionRegistry registry = _registryWith(
          const _UnsupportedExtension(),
        );

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_TestService, String>(
              registry,
              callExtension: _callExt,
              hostFallback: () async =>
                  const ExtensionResultUnsupported<String>(),
            );

        expect(result, isA<ExtensionResultUnsupported<String>>());
      },
    );

    test('host fallback throwing is NOT caught (bugs surface)', () async {
      final ExtensionRegistry registry = _registryWith(null);

      await expectLater(
        ExtensionServiceInvoker.invoke<_TestService, String>(
          registry,
          callExtension: _callExt,
          hostFallback: () async => throw const _HostBoom(),
        ),
        throwsA(isA<_HostBoom>()),
      );
    });

    test(
      'host fallback throwing under hostOnly policy is NOT caught',
      () async {
        final ExtensionRegistry registry = _registryWith(null);

        await expectLater(
          ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async => throw const _HostBoom(),
            policy: ServiceOverridePolicy.hostOnly,
          ),
          throwsA(isA<_HostBoom>()),
        );
      },
    );

    test(
      'host fallback throwing on extensionFirstFallback fallback path is NOT caught',
      () async {
        // Extension is Unsupported -> falls through to host -> host throws.
        final ExtensionRegistry registry = _registryWith(
          const _UnsupportedExtension(),
        );

        await expectLater(
          ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            hostFallback: () async => throw const _HostBoom(),
          ),
          throwsA(isA<_HostBoom>()),
        );
      },
    );

    test('extensionOnly + extension throws: Failure preserved', () async {
      final ExtensionRegistry registry = _registryWith(
        const _ThrowingExtension(),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
            policy: ServiceOverridePolicy.extensionOnly,
          );

      expect(result, isA<ExtensionResultFailure<String>>());
    });
  });

  group('ExtensionServiceInvoker — ExtensionResult<void> smoke test', () {
    test(
      'extension returning ExtensionResultOk<void> produces an Ok wrapper',
      () async {
        final ExtensionRegistry registry = ExtensionRegistry();
        registry.registerService<_VoidExtension>(_OkVoidExtension());

        final ExtensionResult<void> result =
            await ExtensionServiceInvoker.invoke<_VoidExtension, void>(
              registry,
              callExtension: (_VoidExtension s) => s.run(),
            );

        expect(result, isA<ExtensionResultOk<void>>());
      },
    );

    test('extension throwing produces a Failure wrapper for void', () async {
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.registerService<_VoidExtension>(_ThrowingVoidExtension());

      final ExtensionResult<void> result =
          await ExtensionServiceInvoker.invoke<_VoidExtension, void>(
            registry,
            callExtension: (_VoidExtension s) => s.run(),
            policy: ServiceOverridePolicy.extensionOnly,
          );

      expect(result, isA<ExtensionResultFailure<void>>());
    });
  });
}

class _CountingExtension implements _TestService {
  _CountingExtension(this._onCall);
  final void Function() _onCall;

  @override
  Future<ExtensionResult<String>> hello() async {
    _onCall();
    return const ExtensionResultOk<String>('ext:counted');
  }
}

abstract class _VoidExtension {
  Future<ExtensionResult<void>> run();
}

class _OkVoidExtension implements _VoidExtension {
  @override
  Future<ExtensionResult<void>> run() async =>
      const ExtensionResultOk<void>(null);
}

class _ThrowingVoidExtension implements _VoidExtension {
  @override
  Future<ExtensionResult<void>> run() async => throw const _ExtensionBoom();
}
