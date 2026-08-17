plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.saanvi"
    // deepar_flutter_plus requires compileSdk 35+ (16KB page size support) —
    // explicit floor rather than trusting flutter.compileSdkVersion, which
    // tracks the Flutter SDK's own default and isn't guaranteed to meet a
    // third-party plugin's specific requirement.
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.saanvi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // deepar_flutter_plus requires minSdk 23+ — same explicit-floor
        // reasoning as compileSdk above.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Referenced per deepar_flutter_plus's README even though this
            // buildType doesn't enable isMinifyEnabled — harmless either
            // way, and correctly primed for if/when minification is turned
            // on (a separate decision from this DeepAR integration).
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

// deepar_flutter_plus's native Android SDK ships as a manually-downloaded
// .aar (license-gated, not on a public Maven repo) — per its README, download
// from https://developer.deepar.ai/downloads and place at android/app/libs/
// deepar.aar. This fileTree dependency picks up whatever's placed there;
// the app will fail to build until that file exists.
dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}

flutter {
    source = "../.."
}
