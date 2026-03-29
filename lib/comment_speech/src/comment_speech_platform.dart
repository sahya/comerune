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
}
