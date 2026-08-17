import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Emoji particles flying outward/fading from a tap point, for the
/// double-tap react gesture. Self-disposing — call [onComplete] to have
/// the caller remove it from its Stack/Overlay.
class EmojiBurst extends StatefulWidget {
  const EmojiBurst({
    super.key,
    required this.origin,
    required this.emoji,
    required this.onComplete,
    this.particleCount = 7,
  });

  final Offset origin;
  final String emoji;
  final VoidCallback onComplete;
  final int particleCount;

  @override
  State<EmojiBurst> createState() => _EmojiBurstState();
}

class _Particle {
  _Particle({required this.angle, required this.distance, required this.size, required this.delay});
  final double angle;
  final double distance;
  final double size;
  final double delay;
}

class _EmojiBurstState extends State<EmojiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward().whenComplete(widget.onComplete);

  late final List<_Particle> _particles = List.generate(widget.particleCount, (i) {
    final rng = math.Random(i * 97 + widget.origin.dx.toInt());
    return _Particle(
      angle: (i / widget.particleCount) * 2 * math.pi + rng.nextDouble() * 0.6,
      distance: 50 + rng.nextDouble() * 45,
      size: 20 + rng.nextDouble() * 14,
      delay: rng.nextDouble() * 0.15,
    );
  });

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            children: [
              for (final p in _particles) _buildParticle(p),
            ],
          );
        },
      ),
    );
  }

  Widget _buildParticle(_Particle p) {
    final t = ((_ctrl.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);
    final dx = math.cos(p.angle) * p.distance * eased;
    final dy = math.sin(p.angle) * p.distance * eased - (20 * eased);
    final opacity = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);
    final scale = 0.6 + 0.6 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0)) * (1 - t * 0.3);

    return Positioned(
      left: widget.origin.dx + dx - p.size / 2,
      top: widget.origin.dy + dy - p.size / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Text(widget.emoji, style: TextStyle(fontSize: p.size)),
        ),
      ),
    );
  }
}
