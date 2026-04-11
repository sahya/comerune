# Flutter engine
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# VOICEVOX JNI bridge (native methods must not be renamed)
-keep class com.example.comerune.speech.infrastructure.engine.NativeVoicevoxBridge { *; }
