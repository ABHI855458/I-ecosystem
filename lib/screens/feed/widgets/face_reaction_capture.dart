import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants.dart';
import 'center_select_rail.dart';
import 'reaction_camera_filters.dart';

// ---------------------------------------------------------------------------
// FaceReactionCapture — "Send a reaction" full-screen camera, rebuilt to
// design-refs/design_handoff_group_post_cards 2/README-camera.md +
// reference-camera.html: circular viewfinder, horizontally scrolling filter
// rail with a fixed center shutter, and (when the emoji hasn't already been
// chosen upstream) a second center-selection carousel for the reaction.
//
// Public API unchanged from the old bottom-sheet version — every existing
// caller (RealmojiTray's empty-slot capture, the preset-add flow) keeps
// working untouched; only the presentation moved from showModalBottomSheet
// to a full-screen push (see each call site), matching "a full-screen
// capture flow" in the spec's Overview.
// ---------------------------------------------------------------------------

class FaceReactionResult {
  const FaceReactionResult({required this.selfie, required this.emoji});
  final File selfie;
  final String emoji;
}

/// Reactions, in spec order — only ever reachable when [FaceReactionCapture
/// .presetEmoji] is null (no caller currently does this; every existing
/// call site picks the RealmojiType/emoji before opening the camera, so
/// this rail exists for a future "pick emoji here" caller without breaking
/// today's locked-emoji flow).
const kReactionCameraEmojis = [
  '👍', '❤️', '😂', '😍', '🔥', '😮', '🥲', '😭', '🥳', '💯',
  '👏', '🙌', '🤯', '😎', '🫶', '😴', '🤝', '✨', '🙃', '😤',
];

class FaceReactionCapture extends StatefulWidget {
  const FaceReactionCapture({
    super.key,
    required this.onFallbackToEmoji,
    this.presetEmoji,
    this.title = 'Send a reaction',
    this.accentColor = AppColors.coral,
  });

  /// Called when the front camera isn't available (denied permission, no
  /// front lens, init failure) and the user chooses to react with an emoji
  /// instead. The widget pops itself with null right after.
  final VoidCallback onFallbackToEmoji;

  /// When set, the emoji was already chosen UPSTREAM (RealmojiTray's
  /// per-type empty slot) — the reaction rail is replaced with a small
  /// fixed badge showing it instead of a pickable carousel, since there's
  /// nothing left to choose. Null shows the full reaction rail.
  final String? presetEmoji;

  final String title;

  /// Selected-state ring/pill tint — defaults to the coral every existing
  /// caller already expects; RealMoji's own callers pass neonCyan.
  final Color accentColor;

  @override
  State<FaceReactionCapture> createState() => _FaceReactionCaptureState();
}

enum _CamState { idle, initializing, live, captured, unavailable }

class _FaceReactionCaptureState extends State<FaceReactionCapture> {
  CameraController? _controller;
  _CamState _state = _CamState.idle;
  String? _errorMessage;
  Uint8List? _captureBytes;
  File? _captureFile;
  bool _processing = false;
  bool _saved = false;
  Timer? _savedTimer;

  int _filterIndex = 3;
  int _reactionIndex = 3;

  @override
  void dispose() {
    _savedTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    if (_state == _CamState.initializing || _state == _CamState.live) return;
    setState(() {
      _state = _CamState.initializing;
      _errorMessage = null;
    });
    try {
      final cameras = await availableCameras();
      final front =
          cameras.where((c) => c.lensDirection == CameraLensDirection.front).toList();
      if (front.isEmpty) {
        if (!mounted) return;
        setState(() {
          _state = _CamState.unavailable;
          _errorMessage = 'No camera available here. Open on a device to use it.';
        });
        return;
      }
      final ctrl = CameraController(front.first, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _state = _CamState.live;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('denied') ||
          e.code.toLowerCase().contains('permission');
      setState(() {
        _state = _CamState.unavailable;
        _errorMessage = denied
            ? 'Camera blocked — allow access in Settings'
            : 'No camera available here. Open on a device to use it.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _CamState.unavailable;
        _errorMessage = 'No camera available here. Open on a device to use it.';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _processing) return;
    HapticFeedback.mediumImpact();
    setState(() => _processing = true);
    try {
      final raw = await controller.takePicture();
      final bytes = await File(raw.path).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('decode failed');
      final side = math.min(decoded.width, decoded.height);
      final ox = (decoded.width - side) ~/ 2;
      final oy = (decoded.height - side) ~/ 2;
      decoded = img.copyCrop(decoded, x: ox, y: oy, width: side, height: side);
      // Preview is mirrored (Transform.scale(scaleX: -1) on CameraPreview
      // below) — the saved/sent photo is mirrored the same way so it
      // matches what the user actually saw, per spec.
      decoded = img.flipHorizontal(decoded);
      decoded = ReactionFilter.all[_filterIndex].apply(decoded);
      final jpg = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));

      final tmp = File(
        '${Directory.systemTemp.path}/reaction_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmp.writeAsBytes(jpg);

      if (!mounted) return;
      setState(() {
        _captureBytes = jpg;
        _captureFile = tmp;
        _state = _CamState.captured;
        _processing = false;
      });
    } catch (e, st) {
      debugPrint('[FaceReactionCapture._capture] failed: $e\n$st');
      if (mounted) setState(() => _processing = false);
    }
  }

  void _retake() {
    setState(() {
      _captureBytes = null;
      _captureFile = null;
      _saved = false;
      _state = _CamState.live;
    });
  }

  Future<void> _savePhoto() async {
    final bytes = _captureBytes;
    final file = _captureFile;
    if (bytes == null || file == null || _saved) return;
    HapticFeedback.lightImpact();
    try {
      await Gal.putImageBytes(bytes, name: 'reaction_${DateTime.now().millisecondsSinceEpoch}');
    } catch (e, st) {
      // Gallery permission denied or unavailable — the reaction itself
      // doesn't depend on the gallery write, so this never blocks sending
      // it, only the "Saved" confirmation is skipped.
      debugPrint('[FaceReactionCapture._savePhoto] gallery write failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() => _saved = true);
    _savedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final emoji = widget.presetEmoji ?? kReactionCameraEmojis[_reactionIndex];
      Navigator.of(context).pop(FaceReactionResult(selfie: file, emoji: emoji));
    });
  }

  void _useEmojiInstead() {
    widget.onFallbackToEmoji();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111114),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFF2F2F4),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Capture your own take on the reaction, then pick which one to send.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: const Color(0xFF9A9AA5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: Center(child: _buildViewfinder())),
            SizedBox(
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CenterSelectRail(
                    itemCount: ReactionFilter.all.length,
                    itemExtent: 74,
                    initialIndex: _filterIndex,
                    onSelectedChanged: (i) => setState(() => _filterIndex = i),
                    itemBuilder: (context, i, selected) =>
                        _FilterChip(filter: ReactionFilter.all[i], selected: selected),
                  ),
                  _ShutterButton(
                    filter: ReactionFilter.all[_filterIndex],
                    busy: _processing,
                    onTap: () {
                      if (_state == _CamState.idle || _state == _CamState.unavailable) {
                        _openCamera();
                      } else if (_state == _CamState.live) {
                        _capture();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              ReactionFilter.all[_filterIndex].name.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                letterSpacing: 0.08 * 11,
                color: const Color(0xFFF2F2F4),
              ),
            ),
            if (_state == _CamState.captured) ...[
              const SizedBox(height: 14),
              _RetakeSaveRow(saved: _saved, onRetake: _retake, onSave: _savePhoto),
            ],
            const SizedBox(height: 14),
            if (widget.presetEmoji == null)
              _ReactionRailSection(
                accentColor: widget.accentColor,
                initialIndex: _reactionIndex,
                onSelectedChanged: (i) => setState(() => _reactionIndex = i),
              )
            else
              _LockedReactionBadge(emoji: widget.presetEmoji!, accentColor: widget.accentColor),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    return Container(
      width: 248,
      height: 248,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        border: Border.all(color: const Color(0xFF1C1C22), width: 3),
      ),
      child: ClipOval(child: _viewfinderContent()),
    );
  }

  Widget _viewfinderContent() {
    switch (_state) {
      case _CamState.idle:
        return GestureDetector(
          onTap: _openCamera,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📷', style: TextStyle(fontSize: 34)),
                const SizedBox(height: 8),
                Text(
                  'tap to open camera',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: const Color(0xFF5C5C66)),
                ),
              ],
            ),
          ),
        );
      case _CamState.initializing:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        );
      case _CamState.unavailable:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚫', style: TextStyle(fontSize: 30)),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'No camera available here. Open on a device to use it.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    height: 1.5,
                    color: const Color(0xFFFF8A7A),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _useEmojiInstead,
                  child: Text(
                    'React with an emoji instead',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _CamState.live:
        final controller = _controller!;
        return GestureDetector(
          onTap: _capture,
          child: Transform.scale(
            scaleX: -1,
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(ReactionFilter.all[_filterIndex].colorFilterMatrix),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? 1,
                  height: controller.value.previewSize?.width ?? 1,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
        );
      case _CamState.captured:
        return Image.memory(_captureBytes!, fit: BoxFit.cover);
    }
  }
}

// ---------------------------------------------------------------------------
// Filter rail chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter, required this.selected});
  final ReactionFilter filter;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFF2F2F4) : const Color(0xFF23232B),
          width: 2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: filter.swatchGradient,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fixed shutter button, pinned at the filter rail's exact center.
// ---------------------------------------------------------------------------

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.filter, required this.busy, required this.onTap});
  final ReactionFilter filter;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: busy,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0E0E11),
            border: Border.all(color: const Color(0xFFF2F2F4), width: 5),
            boxShadow: const [
              BoxShadow(color: Color(0xE60A0A0C), blurRadius: 0, spreadRadius: 4),
              BoxShadow(color: Color(0x8C000000), blurRadius: 26, offset: Offset(0, 10)),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: filter.swatchGradient,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x47FFFFFF), blurRadius: 10, offset: Offset(0, 3)),
                BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, -6)),
              ],
            ),
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Retake / Save row — only shown after a capture.
// ---------------------------------------------------------------------------

class _RetakeSaveRow extends StatelessWidget {
  const _RetakeSaveRow({required this.saved, required this.onRetake, required this.onSave});
  final bool saved;
  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onRetake,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C22),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Retake',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: saved ? null : onSave,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F4),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              saved ? 'Saved ✓' : 'Save photo',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0E0E11)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction rail — only reachable when presetEmoji is null (see class doc).
// ---------------------------------------------------------------------------

class _ReactionRailSection extends StatelessWidget {
  const _ReactionRailSection({
    required this.accentColor,
    required this.initialIndex,
    required this.onSelectedChanged,
  });

  final Color accentColor;
  final int initialIndex;
  final ValueChanged<int> onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'SWIPE TO CHOOSE A REACTION',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            letterSpacing: 0.1 * 11,
            color: const Color(0xFF6F6F7A),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 66,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CenterSelectRail(
                itemCount: kReactionCameraEmojis.length,
                itemExtent: 68,
                initialIndex: initialIndex,
                onSelectedChanged: onSelectedChanged,
                itemBuilder: (context, i, selected) => Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1C1C22)),
                  child: Center(
                    child: Text(kReactionCameraEmojis[i], style: const TextStyle(fontSize: 23)),
                  ),
                ),
              ),
              IgnorePointer(
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF2F2F4), width: 4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x24F2F2F4), blurRadius: 0, spreadRadius: 3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The emoji was already chosen upstream (RealmojiTray's per-type slot) —
/// shown in the reaction rail's footprint as a static, non-interactive
/// badge instead of the full carousel, since there's nothing left to pick.
class _LockedReactionBadge extends StatelessWidget {
  const _LockedReactionBadge({required this.emoji, required this.accentColor});
  final String emoji;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Center(
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1C1C22),
            border: Border.all(color: accentColor, width: 2.5),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
        ),
      ),
    );
  }
}
