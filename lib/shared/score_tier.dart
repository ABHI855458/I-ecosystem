import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Tier definitions
// ---------------------------------------------------------------------------

enum ScoreTier { lurker, active, prominent, legend }

class ScoreTierInfo {
  const ScoreTierInfo({
    required this.tier,
    required this.title,
    required this.color,
    required this.glowBlur,
    required this.glowAlpha,
    required this.minScore,
    this.maxScore,
  });

  final ScoreTier tier;
  final String title;
  final Color color;
  final double glowBlur;
  final double glowAlpha;
  final int minScore;
  final int? maxScore;
}

const _tiers = [
  ScoreTierInfo(
    tier: ScoreTier.lurker,
    title: 'Lurker',
    color: Color(0xFF405DE6), // Instagram blue — subtle ring
    glowBlur: 6,
    glowAlpha: 0.35,
    minScore: 0,
    maxScore: 50,
  ),
  ScoreTierInfo(
    tier: ScoreTier.active,
    title: 'Active',
    color: Color(0xFF833AB4), // Instagram purple — moderate ring
    glowBlur: 12,
    glowAlpha: 0.50,
    minScore: 51,
    maxScore: 150,
  ),
  ScoreTierInfo(
    tier: ScoreTier.prominent,
    title: 'Prominent',
    color: Color(0xFFE1306C), // Instagram pink — bright pulsing ring
    glowBlur: 22,
    glowAlpha: 0.70,
    minScore: 151,
    maxScore: 400,
  ),
  ScoreTierInfo(
    tier: ScoreTier.legend,
    title: 'Legend',
    color: Color(0xFFF77737), // Instagram orange — full-gradient shimmer
    glowBlur: 32,
    glowAlpha: 0.90,
    minScore: 401,
  ),
];

ScoreTierInfo tierInfoForScore(int score) {
  for (final t in _tiers.reversed) {
    if (score >= t.minScore) return t;
  }
  return _tiers.first;
}

double tierProgressToNext(int score) {
  final info = tierInfoForScore(score);
  if (info.maxScore == null) return 1.0;
  final rangeStart = info.minScore;
  final rangeEnd = info.maxScore!;
  return ((score - rangeStart) / (rangeEnd - rangeStart)).clamp(0.0, 1.0);
}

int? nextTierThreshold(int score) {
  final info = tierInfoForScore(score);
  return info.maxScore == null ? null : info.maxScore! + 1;
}

// Points remaining to next tier (rounded to nearest 5 for mystery)
int? pointsToNextTier(int score) {
  final next = nextTierThreshold(score);
  if (next == null) return null;
  final exact = next - score;
  // Round up to nearest 5 to keep it slightly vague
  return (exact / 5).ceil() * 5;
}

// ---------------------------------------------------------------------------
// Dummy user scores
// ---------------------------------------------------------------------------

const userScores = <String, int>{
  'abhishek_patel': 230,
  'alex_xyz': 340,
  'jordan_23': 89,
  'study_bug': 450,
  'sunset_chaser': 180,
  'coffee_talk': 40,
  'library_mode': 120,
  'fest_vibes': 210,
  'campus_life': 75,
};

int scoreForUser(String username) => userScores[username] ?? 60;

// ---------------------------------------------------------------------------
// Shimmer ring painter — rotating bright spot for Legend tier
// ---------------------------------------------------------------------------

class _ShimmerRingPainter extends CustomPainter {
  _ShimmerRingPainter({
    required this.progress,
    required this.color,
    required this.borderWidth,
  });

  final double progress;
  final Color color;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - borderWidth) / 2;

    final startAngle = progress * 2 * math.pi;
    final shader = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + 2 * math.pi,
      colors: [
        Colors.transparent,
        const Color(0xFF405DE6).withValues(alpha: 0.60),
        const Color(0xFF833AB4),
        const Color(0xFFE1306C),
        const Color(0xFFF77737),
        const Color(0xFFE1306C).withValues(alpha: 0.60),
        Colors.transparent,
      ],
      stops: const [0.0, 0.15, 0.35, 0.55, 0.70, 0.85, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_ShimmerRingPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// ScoreGlowRing — wraps any child in a tier-colored glow ring
//
// flashBoost > 1.0 temporarily multiplies the glow (for level-up animation).
// ---------------------------------------------------------------------------

class ScoreGlowRing extends StatefulWidget {
  const ScoreGlowRing({
    super.key,
    required this.score,
    required this.size,
    required this.child,
    this.borderWidth = 2.0,
    this.flashBoost = 1.0,
  });

  final int score;
  final double size;
  final Widget child;
  final double borderWidth;
  final double flashBoost;

  @override
  State<ScoreGlowRing> createState() => _ScoreGlowRingState();
}

class _ScoreGlowRingState extends State<ScoreGlowRing>
    with TickerProviderStateMixin {
  // Tier 3 — subtle breathe pulse
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  // Tier 4 — shimmer rotation
  AnimationController? _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _setupAnimations(widget.score);
  }

  @override
  void didUpdateWidget(ScoreGlowRing old) {
    super.didUpdateWidget(old);
    if (tierInfoForScore(old.score).tier != tierInfoForScore(widget.score).tier) {
      _pulseCtrl?.dispose();
      _shimmerCtrl?.dispose();
      _pulseCtrl = null;
      _shimmerCtrl = null;
      _pulseAnim = null;
      _setupAnimations(widget.score);
    }
  }

  void _setupAnimations(int score) {
    final tier = tierInfoForScore(score).tier;

    if (tier == ScoreTier.prominent || tier == ScoreTier.legend) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat(reverse: true);
      _pulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
      );
    }

    if (tier == ScoreTier.legend) {
      _shimmerCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    _shimmerCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(widget.score);

    if (_pulseAnim != null || _shimmerCtrl != null) {
      final listenables = <Listenable>[
        ?_pulseAnim,
        ?_shimmerCtrl,
      ];
      return AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (ctx, snap) => _buildRing(
          info,
          pulseAlpha: _pulseAnim?.value ?? 1.0,
          shimmerProgress: _shimmerCtrl?.value,
        ),
      );
    }
    return _buildRing(info, pulseAlpha: 1.0, shimmerProgress: null);
  }

  Widget _buildRing(
    ScoreTierInfo info, {
    required double pulseAlpha,
    required double? shimmerProgress,
  }) {
    final boost = widget.flashBoost.clamp(1.0, 5.0);
    final effectiveAlpha = (info.glowAlpha * pulseAlpha * boost).clamp(0.0, 1.0);
    final effectiveBlur = info.glowBlur * (boost > 1.0 ? boost * 0.6 : 1.0);

    final ring = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: info.color.withValues(alpha: effectiveAlpha.clamp(0.0, 1.0)),
          width: widget.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: info.color.withValues(alpha: effectiveAlpha * 0.70),
            blurRadius: effectiveBlur,
            spreadRadius: effectiveBlur * 0.08,
          ),
          if (info.tier == ScoreTier.legend)
            BoxShadow(
              color: Colors.white.withValues(
                  alpha: (effectiveAlpha * 0.30 * (1.0 - pulseAlpha))
                      .clamp(0.0, 1.0)),
              blurRadius: effectiveBlur * 0.4,
              spreadRadius: 0,
            ),
        ],
      ),
      child: ClipOval(child: widget.child),
    );

    if (shimmerProgress == null) return ring;

    // Tier 4 — overlay rotating shimmer arc on top of the base ring
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          ring,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ShimmerRingPainter(
                  progress: shimmerProgress,
                  color: info.color,
                  borderWidth: widget.borderWidth + 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ScoreGlowAvatar — letter avatar inside a glow ring
// ---------------------------------------------------------------------------

class ScoreGlowAvatar extends StatelessWidget {
  const ScoreGlowAvatar({
    super.key,
    required this.username,
    required this.size,
    this.backgroundColor,
    this.borderWidth = 2.0,
    this.flashBoost = 1.0,
  });

  final String username;
  final double size;
  final Color? backgroundColor;
  final double borderWidth;
  final double flashBoost;

  @override
  Widget build(BuildContext context) {
    final score = scoreForUser(username);
    final info = tierInfoForScore(score);

    return ScoreGlowRing(
      score: score,
      size: size,
      borderWidth: borderWidth,
      flashBoost: flashBoost,
      child: Container(
        color: backgroundColor ?? const Color(0xFF0F0F11),
        child: Center(
          child: Text(
            username[0].toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              fontSize: size * 0.33,
              color: info.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TierBadge — small inline label showing tier title
// ---------------------------------------------------------------------------

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: info.color.withValues(alpha: 0.30)),
      ),
      child: Text(
        info.title.toLowerCase(),
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: info.color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
