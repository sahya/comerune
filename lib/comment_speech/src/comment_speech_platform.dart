import 'models/raw_comment.dart';
import 'models/speech_event.dart';
import 'models/speech_runtime_status.dart';
import 'models/speech_settings.dart';
import 'models/submit_result.dart';

/// Abstract interface for the comment speech platform channel.
///
/// All methods may throw [PlatformException] if the native side reports
/// an error.
abstract class CommentSpeechPlatform {
  Future<void> initialize();
  Future<void> start();
  Future<void> stop({bool clearQueue = false});
  Future<void> skip();
  Future<void> clearQueue();
  Future<SubmitResult> submitComment(RawComment comment);
  Future<void> updateSettings(SpeechSettings settings);
  Future<SpeechRuntimeStatus> getStatus();
  Future<void> release();
  Stream<SpeechEvent> get events;

  Future<List<Map<String, dynamic>>> getAvailableModels();
  Future<void> downloadModel(String modelId);
  Future<void> deleteModel(String modelId);
  Future<List<String>> getDownloadedModels();
  Future<void> loadModel(String modelId);
  Future<void> cancelDownload(String modelId);

  /// Checks whether Android's built-in TTS engine can speak Japanese.
  ///
  /// Returns `true` when the engine is initialized and Japanese language data
  /// is available. Android-only — other platforms should return `false`.
  ///
  /// Side effect: on Android, if the native `AndroidTtsSpeaker` has not been
  /// initialized yet, this call triggers its initialization on demand and
  /// awaits completion before returning. Callers that only want a pure
  /// read-only check should keep this in mind — for Android-TTS-only users
  /// on the comment screen this lazy-init is the intended bootstrap path
  /// (Issue #682). See the native "checkAndroidTtsAvailability" handler in
  /// `CommentSpeechPlugin.kt` for details.
  Future<bool> checkAndroidTtsAvailability();

  /// Opens the device's TTS settings screen (Android only).
  ///
  /// On non-Android platforms this is a no-op.
  Future<void> openAndroidTtsSettings();
}
