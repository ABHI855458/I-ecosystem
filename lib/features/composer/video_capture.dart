import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

// ---------------------------------------------------------------------------
// Shared helpers for hold-to-record video (explicit request, 2026-10-06).
// Both cameras — the task-bar composer and the ping reply camera — use these,
// so what a recorded clip becomes can't drift between them.
// ---------------------------------------------------------------------------

/// A clip too short to be a deliberate hold. A slightly-long tap on the
/// shutter lands here and is dropped rather than sent as a fraction of a
/// second of video.
const kMinVideoMs = 700;

/// A recorded clip plus its poster still.
///
/// The poster matters: posts REQUIRE a still alongside a video
/// (posts_video_needs_poster), every grid/notification that can only show an
/// image needs something to show, and it means [XFile]s handed around the app
/// as "the photo" are always real images — never an mp4 someone tries to
/// decode.
class RecordedClip {
  const RecordedClip({
    required this.video,
    required this.poster,
    required this.ms,
  });

  final XFile video;
  final XFile poster;
  final int ms;
}

/// Pulls a poster frame out of [videoPath]. Returns null if it can't, in
/// which case the caller treats the recording as failed.
Future<XFile?> makeVideoPoster(String videoPath) async {
  try {
    final path = await VideoThumbnail.thumbnailFile(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 1080,
      quality: 85,
      // A beat in, not frame 0 — frame 0 is often black on iOS.
      timeMs: 250,
    );
    if (path == null || !File(path).existsSync()) return null;
    return XFile(path);
  } catch (e, st) {
    debugPrint('[makeVideoPoster] failed: $e\n$st');
    return null;
  }
}

/// Packages a finished recording, or null when it was a mis-hold or the
/// poster couldn't be made.
Future<RecordedClip?> finishClip(XFile video, int? ms) async {
  final len = ms ?? 0;
  if (len < kMinVideoMs) return null;
  final poster = await makeVideoPoster(video.path);
  if (poster == null) return null;
  return RecordedClip(video: video, poster: poster, ms: len);
}
