import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/profile_view_service.dart';
import '../../shared/time_ago.dart';
import 'pinned_section.dart';
import 'profile_navigation.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Viewed by / Pinned — the profile banner's eye sheet. Two tabs: "Viewed by"
// (who viewed MY profile, real data from `profile_views` via
// ProfileViewService) and "Pinned" (up to kMaxPins people pinned via
// PostAuthorPinService, see pinned_section.dart). One eye icon, one sheet —
// deliberately not a second icon on an already-busy banner. Badge count,
// GlassSurface sheet, avatar + name row.
// ---------------------------------------------------------------------------

class ViewedByBannerButton extends StatefulWidget {
  const ViewedByBannerButton({super.key});

  @override
  State<ViewedByBannerButton> createState() => _ViewedByBannerButtonState();
}

class _ViewedByBannerButtonState extends State<ViewedByBannerButton> {
  int _viewerCount = 0;

  /// True when at least one person you PINNED has opened one of your posts.
  /// The badge turns accent for that case — it is the one thing this
  /// control exists to tell you at a glance, without opening anything.
  bool _pinnedSaw = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    // Counts POST viewers, matching what the panel now leads with. It used
    // to count profile visitors, so the badge and the sheet it opened were
    // answering two different questions.
    // Only PINNED people's activity counts (explicit request: "show only
    // the pinned people activities, don't show everyone").
    final people = [
      for (final p in await ProfileViewService.instance.fetchMyPostViewers())
        if (p.isPinned) p,
    ];
    if (!mounted) return;
    setState(() {
      _viewerCount = people.length;
      _pinnedSaw = people.any((p) => p.isPinned);
    });
  }

  Future<void> _open() async {
    // BUG FIX (explicit report): with isScrollControlled:true and no
    // outer `constraints`, the sheet ROUTE itself is free to size up to
    // the full screen on its very first (entrance-transition) layout pass
    // — the inner Container's own maxHeight (ViewedByPanel.build) only
    // constrains its CONTENT, not the route's own initial sizing, so the
    // sheet could render at its larger, route-driven size for that first
    // frame before settling down to the smaller, content-driven one —
    // reading as "opens large, then suddenly becomes small." Passing the
    // same bound directly to `constraints` (the framework's documented
    // way to bound a scroll-controlled sheet) gives the route a known
    // ceiling from the start instead of guessing then correcting.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      builder: (_) => const ViewedByPanel(),
    );
    if (mounted) _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    // The badge sits INSIDE the button's own 40x40 box now (top/right 0,
    // was -3/-3). Clip.none lets a Stack paint outside itself, but it can't
    // stop an ANCESTOR from clipping — and this button lives inside
    // _CollapsibleChrome, whose collapse animation is driven by a ClipRect.
    // That is what sliced the corner off the count blob. Keeping the badge
    // within bounds means no ancestor can cut it, whatever it wraps this in.
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
        ChromeButton(
          // A ring + eye rather than the bare Material outline icon, so it
          // reads as a deliberate mark and as a pair with the RealMoji mark
          // at the other end of the same header row. The ring fills in when
          // someone you pinned has seen your work.
          icon: SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(
              painter: _SeenMarkPainter(
                highlighted: _pinnedSaw,
                accent: PV2.accent,
              ),
            ),
          ),
          onTap: _open,
        ),
        if (_viewerCount > 0)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              decoration: BoxDecoration(
                color: _pinnedSaw ? PV2.accent : const Color(0xFF2E2E33),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFF0A0A0C), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                _viewerCount > 99 ? '99+' : '$_viewerCount',
                style: PV2.body(
                  size: 9.5,
                  weight: FontWeight.w800,
                  color: _pinnedSaw ? PV2.onAccent : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// SeenBannerPill (the profile-banner "Seen" summary pill) removed —
// explicit follow-up. Per-post Seen (DesignSoloCard's own viewerSeen
// pill) is unaffected. ViewedByPanel below is still live — it's also the
// sheet the feed header's own eye opens, unrelated to the removed pill.

class ViewedByPanel extends StatefulWidget {
  const ViewedByPanel({super.key, this.initialTab = 0});

  /// 0 = who opened your POSTS (the feed header's question), 1 = who visited
  /// your PROFILE (the profile's own "Seen" pill). Same sheet either way —
  /// only which half it lands on differs, because the two entry points are
  /// asking two different things.
  final int initialTab;

  @override
  State<ViewedByPanel> createState() => _ViewedByPanelState();
}

class _ViewedByPanelState extends State<ViewedByPanel> {
  bool _loading = true;
  bool _loadError = false;

  /// Who has opened YOUR POSTS — pinned people first (my_post_viewers).
  /// This is the panel's lead tab now. It used to open straight onto
  /// profile visitors, which is a different question and not the one the
  /// eye on the FEED header suggests: checked against the expectation
  /// "does viewed-by show if the pinned people viewed the post", the answer
  /// was no, because nothing here read post_views at all.
  List<PostViewerPerson> _postViewers = const [];

  /// Who visited your profile. Still here, just no longer the headline.
  List<ProfileViewer> _viewers = const [];

  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileViewService.instance.fetchMyPostViewers(),
        ProfileViewService.instance.fetchViewers(),
      ]);
      if (!mounted) return;
      setState(() {
        // Pinned people only — see _loadCount.
        _postViewers = [
          for (final p in results[0] as List<PostViewerPerson>)
            if (p.isPinned) p,
        ];
        _viewers = results[1] as List<ProfileViewer>;
        _loading = false;
        _loadError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _openProfile(String userId) async {
    Navigator.of(context).pop();
    await openProfile(context, userId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        // FIXED height, not a max. All three tabs are now exactly the same
        // size and stay that size — "all the three dropdowns in the eye
        // shall be same size, not changing at all". It was mainAxisSize.min
        // under a maxHeight, so the sheet took whatever height its current
        // tab's content wanted: a 2-row list, a 20-row list and a spinner
        // all produced different sheets, and switching tabs resized it
        // under your finger. The AnimatedSize below then had nothing left
        // to animate, so it is gone too.
        //
        // 0.72 of the screen — bigger than the old content-driven size for
        // the short tabs, which is the other half of the request.
        height: MediaQuery.of(context).size.height * 0.72,
        child: GlassSurface(
          radius: 22,
          fill: const Color(0xF0141416),
          border: const Color(0x14FFFFFF),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeuTabs(
                labels: const ['Your posts', 'Your profile', 'Pinned'],
                selected: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 6),
              Text(
                switch (_tab) {
                  0 => 'Pinned people who opened something you posted.',
                  1 => 'People who visited your profile.',
                  _ => 'The people you pinned.',
                },
                style: PV2.body(size: 11.5, color: PV2.inkCount),
              ),
              const SizedBox(height: 14),
              // Expanded, not Flexible+AnimatedSize: the sheet is a fixed
              // size now, so the body always fills the same space and there
              // is no resize left to animate. Short content sits at the top
              // of that space instead of shrinking the sheet around itself.
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: switch (_tab) {
                    0 => _postViewersBody(),
                    1 => _body(),
                    _ => const SingleChildScrollView(child: PinnedSection()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      // No AnimatedSize sibling: that caused an "opens then visibly
      // resizes" report.
      // No fixed 220 any more — the sheet's own height is fixed, so the
      // spinner centres in whatever the body was handed.
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(color: PV2.accent, strokeWidth: 2),
        ),
      );
    }
    if (_loadError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text("Couldn't load your viewers.", style: PV2.body(size: 13, color: PV2.inkCount)),
        ),
      );
    }
    if (_viewers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            "No one's viewed your profile yet.",
            textAlign: TextAlign.center,
            style: PV2.body(size: 12.5, color: PV2.inkCount),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final v in _viewers) _viewerRow(v)],
      ),
    );
  }

  Widget _postViewersBody() {
    if (_loading) {
      // No fixed 220 any more — the sheet's own height is fixed, so the
      // spinner centres in whatever the body was handed.
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(color: PV2.accent, strokeWidth: 2),
        ),
      );
    }
    if (_loadError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text("Couldn't load this.", style: PV2.body(size: 13, color: PV2.inkCount)),
        ),
      );
    }
    if (_postViewers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            "None of your pinned people have opened your posts yet.",
            textAlign: TextAlign.center,
            style: PV2.body(size: 12.5, color: PV2.inkCount),
          ),
        ),
      );
    }

    final pinned = _postViewers.where((v) => v.isPinned).toList();
    final rest = _postViewers.where((v) => !v.isPinned).toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned viewers are broken out under their own heading rather
          // than merely sorted first — "did the people I pinned see it" is
          // the actual question this panel is opened to answer, and a
          // position in a list doesn't answer it at a glance.
          if (pinned.isNotEmpty) ...[
            _sectionLabel('PINNED · SAW IT'),
            for (final v in pinned) _postViewerRow(v),
            if (rest.isNotEmpty) const SizedBox(height: 10),
          ],
          if (rest.isNotEmpty) ...[
            _sectionLabel(pinned.isEmpty ? 'SEEN BY' : 'EVERYONE ELSE'),
            for (final v in rest) _postViewerRow(v),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          text,
          style: PV2.body(size: 10.5, weight: FontWeight.w700, color: PV2.inkCount),
        ),
      );

  Widget _postViewerRow(PostViewerPerson v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: GestureDetector(
        onTap: v.isPinned ? () => _openProfile(v.userId) : null,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: v.isPinned
                        ? Border.all(color: PV2.accent, width: 1.6)
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(v.isPinned ? 1.6 : 0),
                    child: _avatarCircle(v.avatarUrl, v.isPinned ? 30.8 : 34),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                v.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PV2.body(size: 13.5, weight: FontWeight.w700),
              ),
            ),
            if (v.isPinned) ...[
              Icon(Icons.push_pin_rounded, size: 13, color: PV2.accent),
              const SizedBox(width: 6),
            ],
            Text(
              formatRelativeTime(v.viewedAt, withAgo: true),
              style: PV2.body(size: 11.5, weight: FontWeight.w600, color: PV2.inkByline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewerRow(ProfileViewer v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: GestureDetector(
        onTap: v.isPinned ? () => _openProfile(v.userId) : null,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: v.isPinned
                    ? Border.all(color: PV2.accent, width: 1.6)
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(v.isPinned ? 1.6 : 0),
                child: _avatarCircle(v.avatarUrl, v.isPinned ? 30.8 : 34),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                v.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PV2.body(size: 13.5, weight: FontWeight.w700),
              ),
            ),
            if (v.isPinned) ...[
              Icon(Icons.push_pin_rounded, size: 13, color: PV2.accent),
              const SizedBox(width: 6),
            ],
            Text(
              formatRelativeTime(v.viewedAt, withAgo: true),
              style: PV2.body(size: 11.5, weight: FontWeight.w600, color: PV2.inkByline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarCircle(String? url, double size) {
    return ClipOval(
      child: url == null
          ? Container(width: size, height: size, color: PV2.recessed)
          : CachedNetworkImage(
              memCacheWidth: 1080,
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => Container(width: size, height: size, color: PV2.recessed),
            ),
    );
  }
}


/// The "seen" mark: an eye held inside a ring.
///
/// Replaces Icons.remove_red_eye_outlined, which read as a generic system
/// glyph next to the hand-drawn RealMoji mark on the other end of the same
/// header row. The ring is the shared language between the two; it lights
/// up in the accent when someone you pinned has opened one of your posts,
/// which is the single fact this control exists to surface.
class _SeenMarkPainter extends CustomPainter {
  const _SeenMarkPainter({required this.highlighted, required this.accent});

  final bool highlighted;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    // The mark is ALWAYS the accent blue — explicit correction ("make this
    // icon blue, how it was before"). It had been drawn white in its
    // resting state and only turned accent once a pinned person had seen
    // your work, which meant the common case (nobody pinned has looked
    // yet) rendered a white eye that read as a different, unrelated
    // control next to its accent-colored neighbors.
    //
    // The pinned-saw signal is NOT lost by doing this — it moves entirely
    // into weight instead of hue: a filled ring plus a heavier stroke when
    // highlighted, a hairline ring at 55% when not. Same information, one
    // consistent color.
    const ink = PV2.accent;

    if (highlighted) {
      canvas.drawCircle(
        c,
        s / 2 - s * 0.045,
        Paint()..color = accent.withValues(alpha: 0.18),
      );
    }

    canvas.drawCircle(
      c,
      s / 2 - s * 0.045,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? s * 0.11 : s * 0.09
        ..color = highlighted ? accent : accent.withValues(alpha: 0.55),
    );

    // Almond: two arcs meeting at the corners, drawn as one closed path so
    // the join is clean at this size.
    final w = s * 0.62;
    final h = s * 0.34;
    final path = Path()
      ..moveTo(c.dx - w / 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy - h, c.dx + w / 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy + h, c.dx - w / 2, c.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.085
        ..strokeJoin = StrokeJoin.round
        ..color = ink,
    );
    canvas.drawCircle(c, s * 0.085, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _SeenMarkPainter old) =>
      old.highlighted != highlighted || old.accent != accent;
}
