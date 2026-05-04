// Verifies that the invoker honours the policy override resolved by
// `extension_debug_overrides.dart`.
//
// Like `extension_loader_disabled_filter_test.dart`, this suite
// cannot inject dart-define values at runtime. Instead, it confirms
// that with no override set the default policy is honoured and that
// the invoker delegates correctly. Exhaustive override matrix
// coverage lives in `extension_debug_overrides_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_result.dart';
import 'package:comerune/extension/extension_service_invoker.dart';
import 'package:comerune/extension/service_override_policy.dart';

abstract class _SampleService {
  Future<ExtensionResult<String>> hello();
}

class _OkExtension implements _SampleService {
  const _OkExtension();

  @override
  Future<ExtensionResult<String>> hello() async {
    return const ExtensionResultOk<String>('extension');
  }
}

void main() {
  group('ExtensionServiceInvoker — debug overrides integration (smoke)', () {
    test(
      'with no dart-define set, the explicit policy parameter is honoured',
      () async {
        final ExtensionRegistry registry = ExtensionRegistry();
        registry.registerService<_SampleService>(const _OkExtension());

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_SampleService, String>(
              registry,
              callExtension: (_SampleService s) => s.hello(),
              hostFallback: () async => const ExtensionResultOk<String>('host'),
              policy: ServiceOverridePolicy.hostOnly,
            );

        // hostOnly policy was passed and no override exists, so host
        // wins over the registered extension.
        expect(result, equals(const ExtensionResultOk<String>('host')));
      },
    );

    test(
      'extensionFirstFallback default still routes through the extension',
      () async {
        final ExtensionRegistry registry = ExtensionRegistry();
        registry.registerService<_SampleService>(const _OkExtension());

        final ExtensionResult<String> result =
            await ExtensionServiceInvoker.invoke<_SampleService, String>(
              registry,
              callExtension: (_SampleService s) => s.hello(),
              hostFallback: () async => const ExtensionResultOk<String>('host'),
            );

        expect(result, equals(const ExtensionResultOk<String>('extension')));
      },
    );
  });
}
