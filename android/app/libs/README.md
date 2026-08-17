# DeepAR native Android SDK — manual step required

Download `deepar.aar` from https://developer.deepar.ai/downloads (requires a
free DeepAR developer account, license-gated — not fetchable via `pub get`
or any automated tool) and place it in this directory as:

```
android/app/libs/deepar.aar
```

`android/app/build.gradle.kts`'s `dependencies { implementation(fileTree(...)) }`
block picks up any `.aar` placed here automatically. The app will fail to
build with a missing-class error from anything under `ai.deepar.ar.*` until
this file exists.

For 16KB page size support (required for Google Play compliance on newer
Android versions), use DeepAR Android SDK version 5.6.20 or later.
