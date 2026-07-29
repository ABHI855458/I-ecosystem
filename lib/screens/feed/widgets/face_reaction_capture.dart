import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants.dart';
import '../../../widgets/reaction_picker_popup.dart' show kQuickReactionEmojis;

// ---------------------------------------------------------------------------
// FaceReactionCapture — BeReal-style RealMoji capture.
//
// Deliberately NOT the composer's dual-camera state machine: one
// CameraController, front lens only, no back shot, no compositing. That
// machinery exists to solve a different problem (sequencing two cameras
// into one BeReal-style photo); reacting just needs a fast selfie, and
// re-deriving that whole flow here would be exactly the "rebuild capture"
// this was asked not to do.
//
// Returns a FaceReactionResult via Navigator.pop when the user captures +
// picks an emoji, or pops null if they back out. Actually uploading the
// result is the caller's job (PostCard) — this widget only gets the photo
// and the emoji, it doesn't know about ReactionService.
// ---------------------------------------------------------------------------

class FaceReactionResult {
  const FaceReactionResult({required this.selfie, required this.emoji});
  final File selfie;
  final String emoji;
}

class FaceReactionCapture extends StatefulWidget {
  const FaceReactionCapture({super.key, required this.onFallbackToEmoji});

  /// Called when the front camera isn't available (denied permission, no
  /// front lens, init failure) and the user chooses to react with an emoji
  /// instead. The widget pops itself with null right after.
  final VoidCallback onFallbackToEmoji;

  @override
  State<FaceReactionCapture> createState() => _FaceReactionCaptureState();
}

enum _CamState { initializing, ready, captured, unavailable }

class _FaceReactionCaptureState extends State<FaceReactionCapture> {
  CameraController? _controller;
  _CamState _state = _CamState.initializing;
  XFile? _selfie;
  String? _selectedEmoji;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front =
          cameras.where((c) => c.lensDirection == CameraLensDirection.front).toList();
      if (front.isEmpty) {
        if (mounted) setState(() => _state = _CamState.unavailable);
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
        _state = _CamState.ready;
      });
    } catch (_) {
      // Covers CameraException (permission denied, camera in use elsewhere,
      // etc.) and anything else — all treated the same: no camera, fall
      // back gracefully.
      if (mounted) setState(() => _state = _CamState.unavailable);
    }
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.mediumImpact();
    try {
      final photo = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {
        _selfie = photo;
        _state = _CamState.captured;
      });
    } catch (_) {
      // Shutter failed — stay on the live preview, shutter is still
      // tappable to retry.
    }
  }

  /// Gallery fallback — reachable from both the live-preview screen (a pick
  /// icon beside the shutter) and the unavailable-camera state. Any image
  /// the user already has works here just as well as a fresh selfie; this
  /// widget doesn't care about provenance, only that it ends up with a File
  /// and an emoji before it can pop a result.
  Future<void> _pickFromGallery() async {
    HapticFeedback.selectionClick();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _selfie = picked;
        _state = _CamState.captured;
      });
    } catch (_) {
      // Picker cancelled/denied — stay put, nothing to recover.
    }
  }

  void _retake() {
    setState(() {
      _selfie = null;
      _selectedEmoji = null;
      _state = _CamState.ready;
    });
  }

  void _pickEmoji(String emoji) {
    HapticFeedback.selectionClick();
    setState(() => _selectedEmoji = emoji);
  }

  void _confirm() {
    if (_selfie == null || _selectedEmoji == null) return;
    Navigator.of(context).pop(
      FaceReactionResult(selfie: File(_selfie!.path), emoji: _selectedEmoji!),
    );
  }

  void _useEmojiInstead() {
    widget.onFallbackToEmoji();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 420,
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CamState.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2),
        );
      case _CamState.unavailable:
        return _UnavailableState(onUseEmoji: _useEmojiInstead, onGallery: _pickFromGallery);
      case _CamState.ready:
        return _LivePreview(
          controller: _controller!,
          onCapture: _capture,
          onGallery: _pickFromGallery,
        );
      case _CamState.captured:
        return _EmojiBadgePicker(
          selfie: _selfie!,
          selected: _selectedEmoji,
          onSelect: _pickEmoji,
          onRetake: _retake,
          onConfirm: _confirm,
        );
    }
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.controller,
    required this.onCapture,
    required this.onGallery,
  });
  final CameraController controller;
  final VoidCallback onCapture;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Text(
            'React with your face',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
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
          const SizedBox(height: 16),
          // Gallery pick sits to the left, shutter centered, and a matching
          // blank spacer on the right keeps the shutter mathematically
          // centered rather than nudged left by the gallery icon's width.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: _GalleryButton(onTap: onGallery),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: onCapture,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              const SizedBox(width: 44),
            ],
          ),
        ],
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 18),
      ),
    );
  }
}

class _EmojiBadgePicker extends StatelessWidget {
  const _EmojiBadgePicker({
    required this.selfie,
    required this.selected,
    required this.onSelect,
    required this.onRetake,
    required this.onConfirm,
  });

  final XFile selfie;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(selfie.path), fit: BoxFit.cover),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: GestureDetector(
                      onTap: onRetake,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final emoji in kQuickReactionEmojis) ...[
                _EmojiBadgeOption(
                  emoji: emoji,
                  selected: selected == emoji,
                  onTap: () => onSelect(emoji),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: selected == null ? null : onConfirm,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: selected == null
                    ? AppColors.coral.withValues(alpha: 0.4)
                    : AppColors.coral,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'React',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiBadgeOption extends StatelessWidget {
  const _EmojiBadgeOption({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.coral.withValues(alpha: 0.20) : AppColors.cardSurface,
          border: Border.all(
            color: selected ? AppColors.coral : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onUseEmoji, required this.onGallery});
  final VoidCallback onUseEmoji;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: AppColors.textMuted, size: 32),
            const SizedBox(height: 12),
            Text(
              "Can't access your front camera.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onGallery,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.coral,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Choose a photo instead',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onUseEmoji,
              child: Text(
                'React with an emoji instead',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
