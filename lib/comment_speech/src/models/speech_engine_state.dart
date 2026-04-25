/// Coarse-grained state of the speech (TTS) engine as observed by the
/// comment screen. Replaces the previous String-based representation
/// (`'' / 'READY' / 'ERROR'`) that lived inline in `comment_screen.dart`
/// (Issue #717 / ARCH-2).
///
/// The wire format used on the platform channel
/// (`engine_state_changed.payload.state`) remains the historical
/// uppercase strings; this enum is the **internal** Dart-side
/// representation. Conversion is via [SpeechEngineState.fromWire] —
/// callers MUST go through it instead of building enum values from
/// raw strings, so a future native-side rename surfaces in one place.
///
/// Values
/// * [unknown] — initial state, also re-entered when the controller
///   resets the engine after an error condition (`'' on the wire`).
///   The icon for this state is the neutral "initialising" hourglass.
/// * [ready] — engine reports READY (`'READY'` on the wire). Default
///   running state.
/// * [error] — engine reports ERROR (`'ERROR'` on the wire). The
///   AppBar surfaces this as the error icon and (separately, in #712)
///   a SnackBar.
///
/// Adding a new state will trigger a Dart 3 `switch` exhaustiveness
/// error in every consumer (e.g. `speechIconViewFor` in
/// `comment_screen.dart`), surfacing the addition at compile time.
enum SpeechEngineState {
  unknown,
  ready,
  error;

  /// Wire-format string for [unknown]. Native emits empty string when
  /// the controller is reset to the initial state after a recoverable
  /// failure.
  static const String unknownWire = '';

  /// Wire-format string for [ready].
  static const String readyWire = 'READY';

  /// Wire-format string for [error].
  static const String errorWire = 'ERROR';

  /// Parses a wire-format engine state string emitted by the native
  /// `engine_state_changed` event. Unknown strings map to [unknown]
  /// (defensive default — better than throwing on a payload anomaly
  /// that would tear down the StreamSubscription, see Issue #695
  /// review #7).
  static SpeechEngineState fromWire(String wire) => switch (wire) {
    readyWire => ready,
    errorWire => error,
    _ => unknown,
  };
}
