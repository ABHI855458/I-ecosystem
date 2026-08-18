import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
// CameraDirection isn't re-exported by the package's own barrel file — see
// composer_screen.dart's identical import for why this direct src import is
// required (checked against the installed package source, not a guess).
import 'package:deepar_flutter_plus/src/utils.dart' show CameraDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/deepar_service.dart';
import '../composer/deepar_filter_strip.dart';

// ---------------------------------------------------------------------------
// Data model (shared with ping_screen.dart)
// ---------------------------------------------------------------------------

class PingItem {
  const PingItem({
    required this.senderName,
    required this.avatarColor,
    required this.timeAgo,
    this.prompt = 'Show me your view 👀',
    required this.sentAt,
    this.windowHours = 6,
  });

  final String senderName;
  final Color avatarColor;
  final String timeAgo;
  final String prompt;

  /// When this ping was sent. The reply/re-entry window (see [windowHours])
  /// is measured from here — mirrors the `pings.expires_at` column in
  /// supabase/schema.sql (created_at + the sender-chosen window).
  final DateTime sentAt;

  /// Hours the recipient has to reply before the ping is gone for good.
  /// Sender-configurable at send time (see PingSendSheet); defaults to 6h.
  final int windowHours;
}

// ---------------------------------------------------------------------------
// PingRevealScreen — full-screen immersive hold-to-reveal
//
// Returns bool via pop(true) = pinged back, pop(false) = closed without reply
// ---------------------------------------------------------------------------

class PingRevealScreen extends StatefulWidget {
  const PingRevealScreen({
    super.key,
    required this.ping,
    this.onViewed,
  });

  final PingItem ping;
  final VoidCallback? onViewed;

  @override
  State<PingRevealScreen> createState() => _PingRevealScreenState();
}

class _PingRevealScreenState extends State<PingRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdownCtrl;
  bool _pingBackSent = false;

  @override
  void initState() {
    super.initState();
    _countdownCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener(_onDone);
    _countdownCtrl.forward();
    widget.onViewed?.call();
  }

  @override
  void dispose() {
    _countdownCtrl.dispose();
    super.dispose();
  }

  void _onDone(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      Navigator.of(context).pop(widget.ping.senderName);
    }
  }

  void _pauseCountdown() {
    if (_countdownCtrl.isAnimating) _countdownCtrl.stop();
  }

  void _resumeCountdown() {
    if (!_countdownCtrl.isCompleted && mounted) _countdownCtrl.forward();
  }

  void _pingBack() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PingCameraScreen(
        recipientName: widget.ping.senderName,
        prompt: widget.ping.prompt,
      ),
    ).then((sent) {
      if (sent == true && mounted) {
        setState(() => _pingBackSent = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _pingBackSent = false);
        });
      }
    });
  }

  void _close() => Navigator.of(context).pop(widget.ping.senderName);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) => _pauseCountdown(),
        onPointerUp: (_) => _resumeCountdown(),
        onPointerCancel: (_) => _resumeCountdown(),
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 400) _close();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: widget.ping.avatarColor),
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Story countdown bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: AnimatedBuilder(
                        animation: _countdownCtrl,
                        builder: (context, child) => ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: 1.0 - _countdownCtrl.value,
                            minHeight: 3.5,
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    ),

                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _close,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'reply from',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.48)),
                              ),
                              Text(
                                widget.ping.senderName,
                                style: GoogleFonts.jetBrainsMono(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Photo card — locket style
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: AspectRatio(
                          aspectRatio: 3.0 / 4.0,
                          child: Container(
                            color: widget.ping.avatarColor,
                            child: Center(
                              child: Text(
                                widget.ping.senderName[0].toUpperCase(),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 120,
                                  color: Colors.white.withValues(alpha: 0.10),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Text(
                      'Hold to pause',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.40)),
                    ),

                    const Spacer(),

                    // Ping-back button
                    Padding(
                      padding: EdgeInsets.fromLTRB(28, 0, 28, bottomPad + 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.ping.timeAgo,
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white.withValues(alpha: 0.36)),
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: _pingBackSent ? null : _pingBack,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: _pingBackSent
                                    ? null
                                    : const LinearGradient(
                                        colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: _pingBackSent ? Colors.white.withValues(alpha: 0.18) : null,
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: _pingBackSent
                                    ? []
                                    : [BoxShadow(color: const Color(0xFF833AB4).withValues(alpha: 0.55), blurRadius: 28, offset: const Offset(0, 8))],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _pingBackSent ? 'Sent ✓' : 'PING BACK?',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (!_pingBackSent) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PingCameraScreen — 85% bottom-sheet dual camera for ping reply
//
// Returns bool via pop(true) = sent, pop(false) = closed without sending
// ---------------------------------------------------------------------------

class PingCameraScreen extends StatefulWidget {
  const PingCameraScreen({
    super.key,
    required this.recipientName,
    this.prompt = 'Show me your view 👀',
  });

  final String recipientName;
  final String prompt;

  @override
  State<PingCameraScreen> createState() => _PingCameraScreenState();
}

class _PingCameraScreenState extends State<PingCameraScreen>
    with SingleTickerProviderStateMixin {
  bool _sending = false;
  bool _sent = false;
  bool _initFailed = false;
  bool _usingRear = true;
  bool _cameraSwapping = false;
  bool _cameraReady = false;
  // True as soon as DeepAR's initialize() succeeds — see composer_screen.
  // dart's identical field for the full reasoning: on iOS, the native
  // texture (what controller.isInitialized checks) is only set inside
  // DeepArPreviewPlus's own UiKitView.onPlatformViewCreated callback, so
  // gating the preview's mount behind _cameraReady (which itself waits on
  // isInitialized) is a deadlock that can never resolve — reproduced live
  // on-device. Mount the preview on this flag instead, immediately on init
  // success; _cameraReady still gates the filter strip/shutter separately.
  bool _previewMounted = false;

  late final AnimationController _sentCtrl;
  late final Animation<double> _sentScale;

  // Owned by DeepArFilterStrip now (see deepar_filter_strip.dart) — this
  // screen just mirrors the live label for its top pill and holds a key to
  // trigger the capture flash; it no longer tracks/applies lenses itself
  // (that used to be _activeLens/_selectLens/_clearLens).
  String _activeFilterLabel = 'NO FILTER';
  final _flashKey = GlobalKey<CaptureFlashOverlayState>();

  // Ping's lens set — both fun filters plus beautification (no masks here;
  // masks are Anonymous-posting-only, see composer_screen.dart's _lensSet).
  static const _lensSet = [
    DeepArLens.pingFilterOne,
    DeepArLens.pingFilterTwo,
    DeepArLens.beautification,
  ];

  @override
  void initState() {
    super.initState();
    _sentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _sentScale = CurvedAnimation(parent: _sentCtrl, curve: Curves.elasticOut);
    _initDeepAr();
    // Fallback: if camera hasn't opened after 7 s, show gallery option
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      if (!_cameraReady) {
        setState(() => _initFailed = true);
      }
    });
  }

  @override
  void dispose() {
    _sentCtrl.dispose();
    // Fire-and-forget, matching composer_screen.dart's identical dispose —
    // destroy() is idempotent (checked package source) and safe to call
    // even if another screen's init races it.
    DeepArService.instance.dispose();
    super.dispose();
  }

  Future<void> _initDeepAr() async {
    final result = await DeepArService.instance.initializeWithDefaults();
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _previewMounted = false;
        _cameraReady = false;
        _initFailed = true;
      });
      return;
    }
    // Mount the preview NOW, before waiting for isInitialized — see
    // _previewMounted's own doc for why waiting first can never resolve on
    // iOS.
    setState(() => _previewMounted = true);
    // Must wait for the native view to actually exist before touching the
    // controller further — see DeepArService.waitUntilViewReady's own doc
    // for the real on-device crash this prevents.
    final ready = await DeepArService.instance.waitUntilViewReady();
    if (!mounted) return;
    if (!ready) {
      setState(() {
        _previewMounted = false;
        _cameraReady = false;
        _initFailed = true;
      });
      return;
    }
    // DeepAR always starts on the FRONT camera after init/destroy (checked
    // package source: _resetState() hardcodes CameraDirection.front) — flip
    // once to match this screen's existing rear-first default.
    await DeepArService.instance.controller.flipCamera();
    if (!mounted) return;
    setState(() {
      _cameraReady = true;
      _initFailed = false;
      _usingRear = true;
    });
  }

  Future<void> _swapCamera() async {
    if (_cameraSwapping || _sending || !_cameraReady) return;
    setState(() => _cameraSwapping = true);
    try {
      final dir = await DeepArService.instance.controller.flipCamera();
      if (!mounted) return;
      setState(() {
        _usingRear = dir == CameraDirection.rear;
        _cameraSwapping = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraSwapping = false);
    }
  }

  Future<void> _capture() async {
    if (_sending) return;
    _flashKey.currentState?.flash();
    HapticFeedback.mediumImpact();
    try {
      if (_cameraReady) {
        await DeepArService.instance.controller.takeScreenshot();
      }
    } catch (_) {}
    if (!mounted) return;
    _doSend();
  }

  Future<void> _pickGallery() async {
    if (_sending) return;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (image != null && mounted) _doSend();
    } catch (_) {}
  }

  void _doSend() {
    setState(() {
      _sending = true;
      _sent = true;
    });
    HapticFeedback.heavyImpact();
    _sentCtrl.forward();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final pipW = screenW * 0.26;
    final pipH = pipW * 1.38;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        height: screenH * 0.85,
        decoration: BoxDecoration(
          gradient: _sent
              ? const LinearGradient(
                  colors: [Color(0xFF405DE6), Color(0xFF833AB4), Color(0xFFE1306C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: _sent ? null : const Color(0xFF080810),
        ),
        child: _sent ? _buildSentView() : _buildCameraView(bottomPad, pipW, pipH),
      ),
    );
  }

  Widget _buildSentView() {
    return Center(
      child: ScaleTransition(
        scale: _sentScale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send_rounded, color: Colors.white, size: 52),
            const SizedBox(height: 14),
            Text(
              'Sent!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.recipientName,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.70),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(double bottomPad, double pipW, double pipH) {
    return Column(
      children: [
        _buildHeader(),
        _buildPromptDisplay(),
        Expanded(child: _buildCameraArea(pipW, pipH)),
        _buildControls(bottomPad),
      ],
    );
  }

  Widget _buildPromptDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      color: const Color(0xFF060610),
      child: Text(
        widget.prompt,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.3,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'pinging back ${widget.recipientName}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea(double pipW, double pipH) {
    final ready = _previewMounted;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Main camera preview — DeepArPreviewPlus self-sizes via
        // AspectRatio(1/ctrl.aspectRatio); wrapping in an explicit finite
        // SizedBox lets FittedBox(cover) crop-fill the viewfinder, matching
        // the old CameraPreview's full-bleed behavior (identical wrapper to
        // composer_screen.dart's _CameraViewfinder, mirrored here).
        if (ready)
          Builder(builder: (context) {
            final ctrl = DeepArService.instance.controller;
            final ratio = ctrl.aspectRatio;
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 1000 / ratio,
                  height: 1000,
                  child: DeepArPreviewPlus(ctrl),
                ),
              ),
            );
          })
        else if (_initFailed)
          _buildCameraFailedView()
        else
          Container(
            color: const Color(0xFF090912),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'camera loading...',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Capture flash — brief white opacity pulse, triggered by _capture()
        // via _flashKey.
        Positioned.fill(child: CaptureFlashOverlay(key: _flashKey)),

        // Active filter name pill — top-left, clear of the PiP thumbnail on
        // the right.
        if (ready)
          Positioned(
            top: 14,
            left: 16,
            right: pipW + 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActiveFilterPill(label: _activeFilterLabel),
            ),
          ),

        // PiP — tap to swap between rear / front camera
        Positioned(
          top: 14, right: 14,
          child: GestureDetector(
            onTap: _swapCamera,
            child: Container(
              width: pipW, height: pipH,
              decoration: BoxDecoration(
                color: const Color(0xFF12121E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.40), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: _cameraSwapping
                    ? const Center(
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white38)),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _usingRear ? Icons.camera_front_outlined : Icons.camera_rear_outlined,
                            size: 22,
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _usingRear ? 'selfie' : 'rear',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),

        // Bottom scrim
        Positioned(
          bottom: 0, left: 0, right: 0, height: 60,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF090912).withValues(alpha: 0.80),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraFailedView() {
    return Container(
      color: const Color(0xFF090912),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography,
                color: Colors.white.withValues(alpha: 0.25), size: 44),
            const SizedBox(height: 14),
            Text(
              'Camera unavailable',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.60),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Grant camera permission in Settings,\nor use your gallery instead.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.35),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickGallery,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined,
                        color: Colors.white.withValues(alpha: 0.80), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Pick from gallery',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.80),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Filter strip + shutter ring — replaces the old separate DeepArLensPicker
  // (was its own Padding slot in _buildCameraView, above this) and the
  // inline gradient-ring shutter (was the center child of this Row). The
  // ring is the strip's own fixed center, landing where the old shutter
  // used to (between gallery/swap, which stay visible even when the camera
  // isn't ready — same reasoning as composer_screen.dart's identical
  // merge). Horizontal padding moved from the outer Container onto the two
  // side buttons directly, since the strip itself needs the full width for
  // its own center-lock math.
  Widget _buildControls(double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, 18, 0, bottomPad + 26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SizedBox(
        height: 118, // matches DeepArFilterStrip's own height
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_cameraReady)
              if (kDeepArFiltersEnabled)
                DeepArFilterStrip(
                  lenses: _lensSet,
                  onCapture: _capture,
                  onActiveLabelChanged: (l) => setState(() => _activeFilterLabel = l),
                )
              else
                PlainShutterButton(onCapture: _capture),
            Positioned(
              left: 28,
              child: _GlassCamBtn(
                icon: Icons.photo_library_outlined,
                iconSize: 18,
                onTap: _pickGallery,
              ),
            ),
            Positioned(
              right: 28,
              child: _GlassCamBtn(
                icon: Icons.flip_camera_ios_outlined,
                iconSize: 20,
                onTap: _swapCamera,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass camera control button
// ---------------------------------------------------------------------------

class _GlassCamBtn extends StatelessWidget {
  const _GlassCamBtn({
    required this.icon,
    required this.iconSize,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}
