import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// In-memory `WakelockPlusPlatformInterface` for tests.
///
/// `comment_screen_test.dart` and the speech-screen tests need to assert the
/// exact toggle history (e.g. that the screen never disabled the wakelock
/// while a stream is active), so this fake records every `toggle()` call in
/// [toggles]. Tests that only need a platform stub (no history assertions)
/// can ignore the field.
class FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  final List<bool> toggles = <bool>[];
  bool _enabled = false;

  @override
  Future<bool> get enabled async => _enabled;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    _enabled = enable;
  }
}
