import 'package:flutter/foundation.dart';

/// Tri-state result of an Android TTS availability check.
///
/// Values are intentionally enumerated rather than a `bool?` so the unknown
/// state has a name, which keeps both the publishing and the consuming sites
/// honest about distinguishing "not yet checked" from "checked and failed".
enum SpeechAvailability {
  /// No availability check has produced a result yet.
  ///
  /// This is the initial state at app startup before any TTS settings screen
  /// or program connection has run a check. The AppBar must NOT show ERROR
  /// based on this value alone — a real failure has not been observed.
  unknown,

  /// The most recent check confirmed the Android TTS engine has Japanese
  /// voice data available and is ready to speak.
  available,

  /// The most recent check failed: either the engine itself failed to
  /// initialise, the Japanese language data was missing, or the platform
  /// channel raised an exception. The AppBar should reflect this in any
  /// screen that subscribes (e.g. flip the speech status icon to ERROR).
  unavailable,
}

/// Single source of truth for the latest Android-TTS availability result.
///
/// Issue #694: the TTS settings screen and the comment screen both run the
/// `checkAndroidTtsAvailability()` method-channel call but previously stored
/// the result in their own local widget state. As a result the AppBar icon on
/// the comment screen could not reflect a failure detected by the settings
/// screen — e.g. user opens TTS settings, sees "日本語の音声データが利用できま
/// せん", goes back to the comment screen, and the AppBar still shows the
/// happy `volume_up` icon.
///
/// This notifier centralises the latest check result so any screen can
/// publish a fresh result and any other screen can subscribe to render an
/// up-to-date status. The notifier is intentionally Android-TTS-specific:
/// VOICEVOX users have their own setup-helper-driven flow and must not be
/// affected by this notifier.
///
/// Lifecycle: a single instance lives at the app root for the lifetime of
/// the process. Tests may construct their own instance and inject it where
/// needed.
class SpeechAvailabilityNotifier extends ChangeNotifier {
  SpeechAvailability _value = SpeechAvailability.unknown;

  /// The latest known availability result.
  SpeechAvailability get value => _value;

  /// Whether the latest known result is `unavailable`. Subscribers (e.g. the
  /// AppBar speech-status icon) use this as a derived "treat as ERROR" flag
  /// without re-implementing the comparison.
  bool get isUnavailable => _value == SpeechAvailability.unavailable;

  /// Publish that the most recent check confirmed availability.
  void publishAvailable() => _set(SpeechAvailability.available);

  /// Publish that the most recent check confirmed unavailability.
  void publishUnavailable() => _set(SpeechAvailability.unavailable);

  /// Convenience for the common pattern where a `bool` from the platform
  /// check is mapped onto the enum. Centralised so callers do not duplicate
  /// the trivial branch.
  void publish({required bool available}) =>
      available ? publishAvailable() : publishUnavailable();

  /// Reset back to the unknown state. Useful when the active engine changes
  /// from Android TTS to VOICEVOX so the previously-cached Android TTS
  /// result does not influence subsequent rendering.
  void reset() => _set(SpeechAvailability.unknown);

  void _set(SpeechAvailability next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}
