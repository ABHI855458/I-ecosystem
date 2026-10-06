import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// ---------------------------------------------------------------------------
// The app's one video surface — group posts, Duo albums and ping replies all
// render through this (added 2026-10-06 with video support; nothing in the
// app played video before).
//
// Deliberately small: tap to play/pause, muted by default with a speaker
// toggle, a thin progress line, and a duration pill. No scrubbing UI and no
// fullscreen route — these are short clips inside a card, not a player.
//
// Every controller is disposed with its widget, and a clip that fails to
// load falls back to a still frame rather than an error box.
// ---------------------------------------------------------------------------

/// "0:08" from milliseconds — used by cards that only have the stored
/// duration and no loaded controller.
String formatClipDuration(int? ms) {
  if (ms == null || ms <= 0) return '';
  final total = (ms / 1000).round();
  final m = total ~/ 60;
  final sec = (total % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}

class AppVideo extends StatefulWidget {
  const AppVideo({
    super.key,
    this.url,
    this.file,
    this.durationMs,
    this.autoPlay = false,
    this.loop = true,
    this.fit = BoxFit.cover,
    this.showDuration = true,
    this.borderRadius,
  }) : assert(url != null || file != null, 'AppVideo needs a url or a file');

  /// A remote clip (…/video/<id>.mp4) or a local one just recorded/picked.
  final String? url;
  final File? file;

  /// Stored duration, so the pill is right before the file has loaded.
  final int? durationMs;

  final bool autoPlay;
  final bool loop;
  final BoxFit fit;
  final bool showDuration;
  final BorderRadius? borderRadius;

  @override
  State<AppVideo> createState() => _AppVideoState();
}

class _AppVideoState extends State<AppVideo> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final file = widget.file;
    final url = widget.url;
    final c = file != null
        ? VideoPlayerController.file(file)
        : VideoPlayerController.networkUrl(Uri.parse(url!));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(widget.loop);
      await c.setVolume(_muted ? 0 : 1);
      if (widget.autoPlay) await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !_ready) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  void _toggleMute() {
    final c = _c;
    if (c == null || !_ready) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final radius = widget.borderRadius ?? BorderRadius.zero;
    final playing = _ready && (c?.value.isPlaying ?? false);

    Widget body;
    if (_failed || c == null) {
      body = Container(
        color: const Color(0xFF17171C),
        alignment: Alignment.center,
        child: const Icon(
          Icons.videocam_off_rounded,
          color: Colors.white24,
          size: 26,
        ),
      );
    } else if (!_ready) {
      body = Container(
        color: const Color(0xFF17171C),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          // Play badge while paused — the one affordance that says "video".
          if (!playing)
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: .45),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: false,
              padding: EdgeInsets.zero,
              colors: const VideoProgressColors(
                playedColor: Color(0xFF29D3E8),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
          ),
          if (widget.showDuration)
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .45),
                      ),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      color: Colors.black.withValues(alpha: .45),
                    ),
                    child: Text(
                      formatClipDuration(
                        widget.durationMs ?? c.value.duration.inMilliseconds,
                      ),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: ClipRRect(borderRadius: radius, child: body),
    );
  }
}
