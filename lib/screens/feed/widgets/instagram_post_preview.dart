import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// InstagramPostPreview — full-post mockup matching design-refs/Screenshot
// 2026-07-29 at 10.34.18 AM.png (header, caption, photo carousel, progress
// bar), but with the bottom action row swapped for the light heart/comment/
// send/smiley cluster from design-refs/Screenshot 2026-07-29 at 10.36.26 AM
// .png instead of that reference's dark heart-count/comment-count/share bar.
//
// Standalone mockup with hardcoded data — not wired into any real feed, and
// deliberately not built on top of PostCard (PostCard's whole point is never
// showing a name/handle/avatar; this preview needs all three).
// ---------------------------------------------------------------------------

const Color _kClusterGray = Color(0xFF8E8E93);
const double _kClusterIconSize = 17;
const double _kClusterGap = 8;

class InstagramPostPreview extends StatelessWidget {
  const InstagramPostPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PostMock(),
        ),
      ),
    );
  }
}

class _PostMock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          _Header(),
          SizedBox(height: 8),
          _Caption(),
          SizedBox(height: 10),
          _PhotoCarousel(),
          SizedBox(height: 8),
          _ProgressBar(),
          SizedBox(height: 10),
          _LightActionCluster(),
        ],
      ),
    );
  }
}

// ── Header — avatar, name, relative time, overflow menu ─────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF405DE6), Color(0xFFE1306C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'SarahFisher',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        Text(
          '  •  12h',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const Spacer(),
        Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.55), size: 20),
      ],
    );
  }
}

// ── Caption ───────────────────────────────────────────────────────────────

class _Caption extends StatelessWidget {
  const _Caption();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Out here in 🇮🇹 living my best life with my girls. And this view is beautiful.',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 13.5,
        height: 1.35,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );
  }
}

// ── Photo carousel — placeholder art, page pill, expand icon ────────────────

class _PhotoCarousel extends StatelessWidget {
  const _PhotoCarousel();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2E6B7A), Color(0xFF8FD3C6), Color(0xFFDCEFE3)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '1/4',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        return Expanded(
          child: Container(
            height: 2.5,
            margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
            decoration: BoxDecoration(
              color: i == 0 ? Colors.white : Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ── Action cluster — heart / comment / send / smiley + avatars, light pill ──

class _LightActionCluster extends StatelessWidget {
  const _LightActionCluster();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, size: _kClusterIconSize, color: Color(0xFFFF4444)),
                const SizedBox(width: _kClusterGap),
                const Icon(Icons.mode_comment_outlined, size: _kClusterIconSize, color: _kClusterGray),
                const SizedBox(width: _kClusterGap),
                const Icon(Icons.send_outlined, size: _kClusterIconSize, color: _kClusterGray),
                const SizedBox(width: _kClusterGap),
                const Icon(Icons.tag_faces_outlined, size: _kClusterIconSize, color: _kClusterGray),
                const SizedBox(width: _kClusterGap),
                const _AvatarStack(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '12h ago',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _kClusterGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack();

  static const _colors = [Color(0xFFF77737), Color(0xFF405DE6)];

  @override
  Widget build(BuildContext context) {
    const size = _kClusterIconSize + 1;
    return SizedBox(
      width: size + 10,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < _colors.length; i++)
            Positioned(
              left: i * 10,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colors[i],
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
