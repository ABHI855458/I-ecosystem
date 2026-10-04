import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Must come after the Android + Flutter plugins. Processes
    // android/app/google-services.json into FCM resources. No
    // firebase-analytics dependency is added anywhere in this file — see
    // the note in ../settings.gradle.kts.
    id("com.google.gms.google-services")
}

// Release signing credentials, loaded from android/key.properties — gitignored
// (android/.gitignore already covers both key.properties and **/*.jks), so
// the actual passwords/keystore never touch version control. Read as a
// Properties file rather than hardcoded here for exactly that reason: this
// build.gradle.kts file itself IS tracked and readable by anyone with repo
// access, so the secret has to live one level below it.
//
// keystoreProperties stays empty (not null) when the file is absent — e.g. a
// fresh clone with no keystore yet — so `flutter run`/debug builds still
// work; only an actual `release` build reaches into it, and does so via
// requireNotNull below so a missing file fails loudly there instead of
// silently falling back to the debug key (which is the exact bug this
// wiring fixes).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.abhisheksdpatel.iapp"
    // Explicit floor rather than trusting flutter.compileSdkVersion alone:
    // several plugins here (ML Kit, camera) need 35+, and that default
    // tracks the Flutter SDK rather than the plugins.
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs and declares that
        // it REQUIRES core library desugaring. Without this the Android
        // build fails outright at :app:checkDebugAarMetadata:
        //   Dependency ':flutter_local_notifications' requires core library
        //   desugaring to be enabled for :app.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.abhisheksdpatel.iapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ML Kit face detection needs 21+; camera and the notification
        // plugin are happier at 23. Same explicit-floor reasoning as above.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // requireNotNull rather than a silent `?:` fallback: a release
            // build with no key.properties must fail the build, not sign
            // with debug and produce an .aab Play Console will reject (or,
            // worse, one that upload accepts on a fresh app but that can
            // never be used to update it later, since the store binds an
            // app's identity to whichever key first published it).
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = requireNotNull(keystoreProperties.getProperty("keyPassword")) {
                "android/key.properties is missing or incomplete — release builds need it. See android/key.properties.example."
            }
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Primed for if/when minification is turned on — a separate
            // decision from this config.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
