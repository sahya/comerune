abstract class SpeechEngine {
  Future<void> speak(String text);

  // Optional review note:
  // stop() is the only lifecycle operation in v1.2.
  // dispose()/resource-finalization can be added when engine implementations
  // require stronger teardown semantics.
  Future<void> stop();
}
