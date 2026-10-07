# video_thumbnail (vendored)

A copy of `video_thumbnail` 0.5.6 from pub.dev (MIT, see LICENSE), kept in
the repo because the published package cannot be built with this project's
Android toolchain.

**Why:** its `android/build.gradle` calls `jcenter()`, which Gradle 9
removed. From the day the package was added (2026-10-06, for video posters)
every Android build of the app failed at configuration time:

    A problem occurred evaluating project ':video_thumbnail'.
    > Could not find method jcenter() ...

**What changed:** only `android/build.gradle` — the `buildscript` block and
the `jcenter()` repositories are removed, and `compileSdkVersion` /
`minSdkVersion` / `lintOptions` are written in the current DSL. The Dart,
Java and Objective-C sources are untouched.

**To drop this copy:** once a published version builds on Gradle 9, change
the `video_thumbnail` entry in the app's `pubspec.yaml` back to a version
constraint and delete this folder.
