import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';

// ---------------------------------------------------------------------------
// Ping view type
// ---------------------------------------------------------------------------

enum PingViewType { text, photo }

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void showPingViewSheet(
  BuildContext context, {
  required String senderName,
  required PingViewType type,
  String promptText = '',
  Color avatarColor = const Color(0xFF1A2A3A),
}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.90),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, _) => FadeTransition(
        opacity: anim,
        child: PingViewSheet(
          senderName: senderName,
          type: type,
          promptText: promptText,
          avatarColor: avatarColor,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// PingViewSheet — two modes: text (tap) and photo (hold-to-reveal)
// ---------------------------------------------------------------------------

class PingViewSheet extends StatefulWidget {
  const PingViewSheet({
    super.key,
    required this.senderName,
    required this.type,
    this.promptText = '',
    this.avatarColor = const Color(0xFF1A2A3A),
  });

  final String senderName;
  final PingViewType type;
  final String promptText;
  final Color avatarColor;

  @override
  State<PingViewSheet> createState() => _PingViewSheetState();
}

class _PingViewSheetState extends State<PingViewSheet>
    with TickerProviderStateMixin {
  // ── Text ping animations ──────────────────────────────────────────────────
  late final AnimationController _contentCtrl;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  // ── Photo hold animations ─────────────────────────────────────────────────
  late final AnimationController _holdCtrl;
  late final AnimationController _blurCtrl;
  late final Animation<double> _blurAnim;
  bool _photoRevealed = false;
  int _lastHapticSecond = -1;

  @override
  void initState() {
    super.initState();

    // Text: content fades + slides up after 200ms
    _contentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut));

    if (widget.type == PingViewType.text) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _contentCtrl.forward();
      });
    }

    // Photo: hold controller
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _holdCtrl.addListener(_onHoldProgress);
    _holdCtrl.addStatusListener(_onHoldStatus);

    _blurCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _blurAnim = Tween<double>(begin: 22.0, end: 0.0).animate(
      CurvedAnimation(parent: _blurCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _holdCtrl
      ..removeListener(_onHoldProgress)
      ..removeStatusListener(_onHoldStatus)
      ..dispose();
    _blurCtrl.dispose();
    super.dispose();
  }

  // ── Hold mechanics ────────────────────────────────────────────────────────

  void _onHoldProgress() {
    if (_photoRevealed) return;
    final sec = (_holdCtrl.value * 3).floor();
    if (sec > _lastHapticSecond && sec > 0) {
      _lastHapticSecond = sec;
      HapticFeedback.lightImpact();
    }
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_photoRevealed) {
      _revealPhoto();
    }
  }

  void _revealPhoto() {
    setState(() => _photoRevealed = true);
    HapticFeedback.heavyImpact();
    _blurCtrl.forward();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _startHold() {
    if (_photoRevealed) return;
    _lastHapticSecond = 0;
    _holdCtrl.forward();
  }

  void _endHold() {
    if (_photoRevealed) return;
    _holdCtrl.stop();
    _holdCtrl.reset();
    _lastHapticSecond = -1;
    if (mounted) setState(() {});
  }

  // ── Reply actions ─────────────────────────────────────────────────────────

  void _replyWithCamera() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Opening camera...',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        backgroundColor: AppColors.coral,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    Navigator.of(context).pop();
  }

  void _sendOneBack() {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Opening camera — send one back 📷',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        backgroundColor: AppColors.coral,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
        },
        child: widget.type == PingViewType.text
            ? _buildTextPing()
            : _buildPhotoPing(),
      ),
    );
  }

  // ── CASE 1: Text ping ─────────────────────────────────────────────────────

  Widget _buildTextPing() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Atmospheric gradient background
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.3),
              radius: 1.2,
              colors: [
                widget.avatarColor.withValues(alpha: 0.35),
                const Color(0xFF0A0A0C),
              ],
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // Top bar
              _TopBar(
                senderName: widget.senderName,
                label: 'pinged you',
                onClose: () => Navigator.of(context).pop(),
              ),

              const Spacer(),

              // Prompt card — fades + slides in after 200ms
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: _PromptCard(
                      promptText: widget.promptText,
                      senderName: widget.senderName,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Reply area
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: FadeTransition(
                  opacity: _contentFade,
                  child: Column(
                    children: [
                      _ActionButton(
                        icon: Icons.photo_camera_outlined,
                        label: 'Reply with photo',
                        primary: true,
                        onTap: _replyWithCamera,
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Dismiss',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ),
                      ),
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

  // ── CASE 2: Photo reply ───────────────────────────────────────────────────

  Widget _buildPhotoPing() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred photo background
        AnimatedBuilder(
          animation: _blurAnim,
          builder: (context, _) => ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _blurAnim.value,
              sigmaY: _blurAnim.value,
            ),
            child: Container(
              color: widget.avatarColor,
              child: Center(
                child: Text(
                  widget.senderName[0].toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 200,
                    color: Colors.white.withValues(alpha: 0.08),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Vignette — fades on reveal
        AnimatedOpacity(
          opacity: _photoRevealed ? 0.0 : 0.65,
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.25, 1.0],
              ),
            ),
          ),
        ),

        // UI layer
        SafeArea(
          child: Column(
            children: [
              _TopBar(
                senderName: widget.senderName,
                label: 'sent a photo',
                onClose: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              _photoRevealed
                  ? _PhotoRevealedContent(
                      senderName: widget.senderName,
                      onSendBack: _sendOneBack,
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _HoldArea(
                      holdCtrl: _holdCtrl,
                      onPointerDown: _startHold,
                      onPointerUp: _endHold,
                    ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Text(
                  _photoRevealed
                      ? 'disappears after viewing'
                      : 'hold to see the photo',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.35),
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

// ---------------------------------------------------------------------------
// Shared top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.senderName,
    required this.label,
    required this.onClose,
  });

  final String senderName;
  final String label;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ),
              Text(
                senderName,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Prompt card (text ping)
// ---------------------------------------------------------------------------

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.promptText, required this.senderName});

  final String promptText;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.coral.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Coral ping icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: AppColors.coral,
              size: 20,
            ),
          ),
          const SizedBox(height: 18),

          // Prompt text
          Text(
            promptText.isNotEmpty ? promptText : 'Hey! 👋',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),
          Text(
            'from $senderName',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color:
              primary ? AppColors.coral : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: AppColors.coral.withValues(alpha: 0.40),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hold area (photo ping — before reveal)
// ---------------------------------------------------------------------------

class _HoldArea extends StatelessWidget {
  const _HoldArea({
    required this.holdCtrl,
    required this.onPointerDown,
    required this.onPointerUp,
  });

  final AnimationController holdCtrl;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPointerDown(),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerUp(),
      child: AnimatedBuilder(
        animation: holdCtrl,
        builder: (context, _) {
          final progress = holdCtrl.value;
          final secsLeft = (3 - (progress * 3)).ceil().clamp(0, 3);
          final isHolding = progress > 0.005;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 168,
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(168, 168),
                      painter: _RingPainter(
                        progress: progress,
                        color: AppColors.coral,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: isHolding
                          ? Text(
                              '$secsLeft',
                              key: ValueKey(secsLeft),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 42,
                                color: AppColors.coral,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Container(
                              key: const ValueKey('idle'),
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.fingerprint,
                                color: Colors.white.withValues(alpha: 0.55),
                                size: 46,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              AnimatedOpacity(
                opacity: isHolding ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Text(
                  'Hold to reveal',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Revealed content (photo ping — after hold)
// ---------------------------------------------------------------------------

class _PhotoRevealedContent extends StatelessWidget {
  const _PhotoRevealedContent({
    required this.senderName,
    required this.onSendBack,
    required this.onClose,
  });

  final String senderName;
  final VoidCallback onSendBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$senderName sent you a photo',
          style: GoogleFonts.inter(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 36),

        // Send one back
        GestureDetector(
          onTap: onSendBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.coral.withValues(alpha: 0.50),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.photo_camera_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Send one back',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        GestureDetector(
          onTap: onClose,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Close',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Progress ring painter
// ---------------------------------------------------------------------------

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Track ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );

    if (progress <= 0) return;

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963267948966, // -π/2 (top)
      progress * 6.283185307179586, // 2π
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
