import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// Test double for `SharePlatform` that records `share` calls and can be
/// configured to throw.
///
/// Install once before any code accesses `SharePlus.instance` (usually in
/// `setUpAll`) — `SharePlus.instance._platform` is captured on first access
/// and cannot be swapped later.
///
/// Reset `calls` between tests via `setUp`.
class FakeSharePlatform extends SharePlatform {
  FakeSharePlatform();

  final List<ShareParams> calls = <ShareParams>[];

  /// When non-null, `share` throws this error instead of recording the call.
  Object? errorToThrow;

  /// Delay inserted before `share` returns, to simulate slow platform ops
  /// during widget tests (e.g. disabled-button visualisation).
  Duration responseDelay = Duration.zero;

  void reset() {
    calls.clear();
    errorToThrow = null;
    responseDelay = Duration.zero;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    calls.add(params);
    return const ShareResult('', ShareResultStatus.success);
  }
}
