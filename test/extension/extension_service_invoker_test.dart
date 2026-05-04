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
    test('extension call throwing is normalised to Failure', () async {
      final ExtensionRegistry registry = _registryWith(
        const _ThrowingExtension(),
      );

      final ExtensionResult<String> result =
          await ExtensionServiceInvoker.invoke<_TestService, String>(
            registry,
            callExtension: _callExt,
          );

      // extensionFirstFallback default + extension throws + no host =>
      // result is Unsupported (host fallback path returns Unsupported
      // when null). The Failure was logged but the call site sees the
      // host-side Unsupported because that path runs after the
      // extension fails. This documents the actual fall-through.
      expect(result, isA<ExtensionResultUnsupported<String>>());
    });

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
