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

// OAuth BFF host (App Links intent-filter target). Sourced from
// android/oauth_bff.env which is the single source for all three OAuth
// build-time defines (also consumed by `flutter build` via
// --dart-define-from-file). Java Properties().load() parses the same
// KEY=VALUE / # comments format that Flutter's .env loader does. Falls
// back to a non-resolvable .invalid host (RFC 2606) when the contributor
// has not provisioned the file yet, so a missing file cannot
// accidentally bind the intent-filter to a stale/incorrect production
// host.
val oauthBffEnvFile = rootProject.file("oauth_bff.env")
val oauthBffEnv = Properties().apply {
    if (oauthBffEnvFile.exists()) {
        oauthBffEnvFile.inputStream().use { load(it) }
    }
}
val oauthBffHost: String =
    oauthBffEnv.getProperty("OAUTH_BFF_HOST", "oauth-bff.example.invalid")

if (!oauthBffEnvFile.exists()) {
    logger.warn(
        "oauth_bff.env not found — App Links intent-filter will use the " +
        "fallback host '$oauthBffHost' which never resolves. See " +
        "oauth_bff.env.example to configure the real BFF host."
    )
}

val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties().apply {
    if (keyPropsFile.exists()) {
        keyPropsFile.inputStream().use { load(it) }
    }
}

// Values shipped in key.properties.example as illustrative placeholders.
// If they ever appear in key.properties itself, the contributor most likely
// copied the example without filling it in — fall back to debug signing and
// log loudly, so we do not silently produce a "release" APK signed with the
// wrong key. Past incidents: an example-derived key.properties produced an
// APK that ended up debug-signed via Gradle's signingConfig fallback chain,
// which only surfaced months later as a package-conflict on update install.
val placeholderPasswordValues = setOf("your_store_password", "your_key_password")

val keyPropsValid = if (keyPropsFile.exists()) {
    val requiredKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missingKeys = requiredKeys.filter { keyProps.getProperty(it) == null }
    val storePassword = keyProps.getProperty("storePassword") ?: ""
    val keyPassword = keyProps.getProperty("keyPassword") ?: ""
    val hasPlaceholder = storePassword in placeholderPasswordValues ||
        keyPassword in placeholderPasswordValues
    when {
        missingKeys.isNotEmpty() -> {
            logger.warn("key.properties is missing required keys: ${missingKeys.joinToString()}. See key.properties.example.")
            false
        }
        hasPlaceholder -> {
            logger.warn(
                "key.properties contains placeholder values from key.properties.example. " +
                "Falling back to debug signing. Edit android/key.properties with real " +
                "credentials before producing a release APK. See docs/build-guide.md."
            )
            false
        }
        else -> true
    }
} else {
    false
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
        // Inject the OAuth BFF host into AndroidManifest's App Links
        // intent-filter via the ${bffHost} placeholder. Sourced from
        // android/oauth_bff.env so prod values are never committed.
        manifestPlaceholders["bffHost"] = oauthBffHost
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

    if (keyPropsValid) {
        signingConfigs {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
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
            signingConfig = if (keyPropsValid) {
                signingConfigs.getByName("release")
            } else {
                // Fallback to debug signing for local development without key.properties
                // or when key.properties is incomplete.
                signingConfigs.getByName("debug")
            }
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

    testOptions {
        unitTests {
            // Return default values (0 / null / false) for unmocked Android
            // framework methods (e.g. android.util.Log) instead of throwing
            // "Stub!" RuntimeExceptions. Required for pure-JVM unit tests
            // that reference Android SDK types.
            isReturnDefaultValues = true
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    // Real org.json implementation for JVM unit tests. Android's bundled
    // org.json is a stub that throws "Stub!" RuntimeExceptions when called
    // outside an Android runtime, which breaks any test that parses JSON.
    testImplementation("org.json:json:20240303")
}
