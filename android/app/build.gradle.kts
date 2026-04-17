import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val appIdPropsFile = rootProject.file("app_id.properties")
val appIdProps = Properties().apply {
    if (appIdPropsFile.exists()) {
        appIdPropsFile.inputStream().use { load(it) }
    }
}
val configuredAppId: String = appIdProps.getProperty("applicationId", "com.example.comerune")

if (appIdPropsFile.exists() && configuredAppId == "com.example.comerune") {
    logger.warn("app_id.properties exists but applicationId is still the default placeholder.")
}
if (!appIdPropsFile.exists()) {
    logger.warn("app_id.properties not found — using fallback applicationId. See app_id.properties.example.")
}

android {
    namespace = "com.example.comerune"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    defaultConfig {
        applicationId = configuredAppId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            ndk {
                // x86_64: emulator testing only
                abiFilters += "x86_64"
            }
            externalNativeBuild {
                cmake {
                    abiFilters += "x86_64"
                }
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            // Safe: no res/raw/ directory exists in this project, so resource
            // shrinking will not accidentally strip required assets.
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
