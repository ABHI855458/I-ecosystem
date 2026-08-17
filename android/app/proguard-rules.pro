# deepar_flutter_plus — required per its README, or the app can crash in a
# minified release build. Inert unless this project's release buildType
# also enables isMinifyEnabled (currently does not — see build.gradle.kts).
-keepclassmembers class ai.deepar.ar.DeepAR { *; }
-keepclassmembers class ai.deepar.ar.core.videotexture.VideoTextureAndroidJava { *; }
-keep class ai.deepar.ar.core.videotexture.VideoTextureAndroidJava
