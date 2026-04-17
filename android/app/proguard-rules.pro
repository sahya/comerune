# Flutter engine — keep only required subsystems to minimise attack surface
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# VOICEVOX JNI bridge (native methods must not be renamed)
-keep class app.spectacles_software.comerune.speech.infrastructure.engine.NativeVoicevoxBridge { *; }
