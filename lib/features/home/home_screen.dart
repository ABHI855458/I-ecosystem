import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../screens/feed/everyone_feed_screen.dart';
import '../../screens/feed/widgets/post_card_shared.dart'
    show ReactionLibraryButton, openReactionLibrary;
import '../../shared/feed_notif_bar.dart';
import '../../shared/score_tier.dart';
import '../composer/composer_screen.dart';
import 'anonymous_tab.dart';

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenCamera, this.onAnonActiveChanged});

  final VoidCallback? onOpenCamera;

  /// Fired whenever the Anonymous vs Everyone/Friends sub-page (this
  /// screen's own horizontal PageView) changes — MainShell uses this to
  /// decide the floating tab bar's vertical position (Anonymous keeps its
  /// original floating spot; every other page sits lower, Instagram-style).
  final ValueChanged<bool>? onAnonActiveChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pageController = PageController();
  final _notifController = FeedNotifController();
  int _tabIndex = 0;
  // Starts COMPACT, not expanded — a bare "at rest at pixels<=0" check
  // can't tell "just loaded, never scrolled" apart from "scrolled down
  // then explicitly back up to the top", and per _onScrollNotification's
  // own rule those two cases would otherwise both read as "expand". Only
  // the second one should — see _hasScrolledPastThreshold below, which
  // gates that re-expand until a real scroll-down has actually happened.
  bool _chromeCollapsed = true;

  // Bell + reaction-adder row's own collapse state — deliberately NOT
  // _chromeCollapsed. That flag starts collapsed=true on cold start (see
  // its own doc above) specifically to skip a flash of the identity-row/
  // pills; the bell/plus row has no such flash to avoid, so it should just
  // track raw scroll position from frame one — visible at the complete
  // top (including on first load, pixels==0), hidden once scrolled past
  // the same threshold below.
  bool _bellCollapsed = false;
  bool _hasScrolledPastThreshold = false;
  bool _cameraTriggered = false;
  String _selectedCommunity = 'All';

  // Real reserved space for the feed's top inset, replacing the old
  // "just the status bar" constant — measured once, from the header's own
  // rendered height on its first (cold-start / _chromeCollapsed==true,
  // i.e. most-compact) frame, so the feed never starts underneath it. Only
  // measured once, not on every collapse/expand toggle: freezing it here is
  // what keeps AnonymousTab's own "topInset must never change with the
  // header's collapsed state" invariant intact (see that file's doc
  // comment) — the header is still allowed to float OVER the feed during
  // its rarer fully-expanded moments, same as before, just no longer over
  // the ever-present baseline it always falls back to.
  final _headerKey = GlobalKey();
  double? _headerBaselineHeight;

  // Second one-time measurement, same idea as _headerBaselineHeight but
  // captured the first time the header actually reaches its EXPANDED
  // form (widget.collapsed == false) instead of its compact baseline.
  // AnonymousTab intentionally keeps using the frozen compact baseline
  // alone (see its own doc — avoids feed-width-driven aspect-ratio jank),
  // but EveryoneFeedScreen's WallPreviewStrip has no such constraint and
  // was getting covered by the header every time a real user switches
  // tabs, since _switchTab/onPageChanged always land on the EXPANDED
  // header (widget.collapsed = false) — the frozen compact baseline alone
  // under-reserves for that. Captured 240ms after first expanding (past
  // _CollapsibleChrome's 220ms transition) so it reads the settled height,
  // not a mid-animation one; only ever captured once, same as the baseline.
  double? _headerExpandedHeight;

  @override
  void initState() {
    super.initState();
    _updateNotifSuppression();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && mounted) {
        setState(() => _headerBaselineHeight = box.size.height);
      }
    });
  }

  void _captureExpandedHeightOnce() {
    if (_headerExpandedHeight != null) return;
    Future.delayed(const Duration(milliseconds: 240), () {
      if (!mounted || _chromeCollapsed || _headerExpandedHeight != null) return;
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        setState(() => _headerExpandedHeight = box.size.height);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notifController.dispose();
    super.dispose();
  }

  // The prompt bar itself is now pinned and always visible, so it's no
  // longer a useful "moment of relevance" signal. Toasts are suppressed
  // instead while the collapsible chrome (identity row + pills) is still
  // expanded — i.e. right when the user lands on the Anonymous tab, before
  // they've scrolled down at all. Anything pushed during that window stays
  // queued and surfaces once the chrome collapses or the user leaves the tab.
  void _updateNotifSuppression() {
    _notifController.setSuppressed(_tabIndex == 0 && !_chromeCollapsed);
  }

  void _switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() {
      _tabIndex = index;
      _chromeCollapsed = false;
    });
    _captureExpandedHeightOnce();
    _updateNotifSuppression();
    widget.onAnonActiveChanged?.call(index == 0);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _openCamera() {
    if (widget.onOpenCamera != null) {
      widget.onOpenCamera!();
    } else {
      // Fallback only (widget.onOpenCamera is set by MainShell in the real
      // app, which already accounts for the active tab itself) — kept
      // consistent with that path rather than always defaulting Everyone.
      Navigator.of(context)
          .push(openCameraRoute(isAnonymous: _tabIndex == 0));
    }
  }

  // Position-based, not direction-based: the collapsible chrome (tab
  // switcher + identity row + community pills + the viewer-activity toast)
  // is only ever fully shown at the COMPLETE top of the feed (scrollOffset
  // ~0) — any scroll past a small threshold collapses it, and it only
  // reappears once the feed is scrolled all the way back to the top. A
  // small asymmetric gap between the two thresholds (collapse past 8px,
  // reveal only at/below 0px) avoids flicker right at the boundary. Only
  // vertical scrolling counts, so swiping between the Anon/Friends tabs (a
  // horizontal PageView) doesn't trigger this.
  static const double _kCollapseThreshold = 8;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      final pixels = notification.metrics.pixels;
      bool? collapsed;
      // Gated on _hasScrolledPastThreshold: pixels<=0 is also true at the
      // very first frame, before the user has done anything — without the
      // gate this would immediately re-expand the composer on load, right
      // back to the state _chromeCollapsed's own default was just changed
      // to avoid. Once a real scroll-down has happened, it behaves exactly
      // as before (collapses past 8px, re-expands only back at the top).
      if (pixels <= 0 && _hasScrolledPastThreshold) {
        collapsed = false;
      } else if (pixels > _kCollapseThreshold) {
        collapsed = true;
        _hasScrolledPastThreshold = true;
      }
      if (collapsed != null && collapsed != _chromeCollapsed) {
        setState(() => _chromeCollapsed = collapsed!);
        if (!collapsed) _captureExpandedHeightOnce();
        _updateNotifSuppression();
      }

      // Ungated version of the same threshold, for the bell/plus row —
      // see _bellCollapsed's own doc for why this can't reuse `collapsed`
      // above (that one intentionally ignores pixels<=0 until a real
      // scroll-down has happened; the bell row shouldn't).
      final bellCollapsed = pixels > _kCollapseThreshold;
      if (bellCollapsed != _bellCollapsed) {
        setState(() => _bellCollapsed = bellCollapsed);
      }
    }

    // Pull-down-to-camera: iOS overscroll (pixels go negative)
    if (!_cameraTriggered &&
        notification is ScrollUpdateNotification &&
        notification.metrics.pixels < -80) {
      _cameraTriggered = true;
      _openCamera();
    }
    // Pull-down-to-camera: Android overscroll notification
    if (!_cameraTriggered &&
        notification is OverscrollNotification &&
        notification.overscroll > 80) {
      _cameraTriggered = true;
      _openCamera();
    }
    if (notification is ScrollEndNotification) {
      _cameraTriggered = false;
    }

    return false;
  }

  // The bell/reaction row collapses along with the rest of _SlimHeader (see
  // _SlimHeader.build), so nothing in the header is guaranteed on-screen at
  // a fixed size except its cold-start baseline — AnonymousTab.topInset
  // reserves exactly that (status bar + bell row + compact prompt composer,
  // measured once via _headerBaselineHeight, not hand-guessed) rather than
  // just the status bar alone. Still kept constant regardless of collapsed
  // state after that first measurement, same reasoning as before: the
  // feed's available height must never change with the header's collapsed
  // state, or its first post's width-based aspect ratio re-triggers the
  // shrink-then-correct jank AnonymousTab.topInset's own doc comment
  // describes. The header is still allowed to float OVER the feed during
  // its rarer fully-expanded moments (same as always) — only its
  // ever-present baseline gets real reserved space now.

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      // Anonymous = white, Friends = black (confirmed inversion) — see
      // _SlimHeader/_FeedToggle for how the always-visible top chrome
      // (shared across both tabs) adapts to whichever is currently active.
      backgroundColor: _tabIndex == 0 ? Colors.white : AppColors.background,
      // Stack, not Column: the header (toggle + prompt composer + viewer-
      // activity toast) used to be laid out ABOVE the feed in a Column,
      // which meant the feed's available height shrank and grew as that
      // header expanded/collapsed on scroll. Since a post's own size is
      // driven by a width-based aspect ratio with a graceful shrink-to-fit
      // fallback for whatever room remains (see PhotoPostCard.
      // imageAspectRatio), a shrinking parent meant a shrinking post — most
      // visibly on first load, when the header starts fully expanded
      // (least room) and only reaches its final, collapsed size once the
      // user scrolls. Fix: the feed fills the ENTIRE body (Positioned.fill
      // below) and the header floats ON TOP of it as a Stack sibling, same
      // "collapsing app bar over content" pattern MainShell's own floating
      // bell icon uses — but AnonymousTab's `topInset` still reserves real
      // space (the header's own baseline/cold-start height, measured once
      // via _headerKey and then frozen, see _headerBaselineHeight's own
      // doc) so the header's ever-present minimum never overlaps a post.
      // Only the header's rarer fully-EXPANDED moments still float over the
      // feed rather than pushing it down — reserving for that too would
      // reintroduce the shrink-then-correct jank this whole Stack exists to
      // avoid, since expansion is scroll-driven and would make the feed's
      // available height a moving target again.
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) {
                  setState(() {
                    _tabIndex = i;
                    _chromeCollapsed = false;
                  });
                  _captureExpandedHeightOnce();
                  _updateNotifSuppression();
                  widget.onAnonActiveChanged?.call(i == 0);
                },
                children: [
                  AnonymousTab(
                    selectedCommunity: _selectedCommunity,
                    onNotify: _notifController.push,
                    // Falls back to a hand-estimated baseline (status bar +
                    // bell row + compact prompt composer, the header's
                    // smallest/always-present form) for the handful of
                    // frames before _headerBaselineHeight's real measurement
                    // lands — see initState.
                    topInset: _headerBaselineHeight ?? (topPadding + 96),
                  ),
                  EveryoneFeedScreen(
                    chromeCollapsed: _chromeCollapsed,
                    // Unlike AnonymousTab (frozen compact baseline only —
                    // see that call site's own doc), this reserves whichever
                    // of the header's two settled heights currently applies,
                    // since _switchTab/onPageChanged always land here with
                    // the header EXPANDED — a frozen compact-only inset
                    // under-reserves and lets the header cover
                    // WallPreviewStrip. See _headerExpandedHeight's doc.
                    topInset: _chromeCollapsed
                        ? (_headerBaselineHeight ?? (topPadding + 96))
                        : (_headerExpandedHeight ?? (topPadding + 200)),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SlimHeader(
              key: _headerKey,
              activeTab: _tabIndex,
              topPadding: topPadding,
              onTabSwitch: _switchTab,
              collapsed: _chromeCollapsed,
              bellCollapsed: _bellCollapsed,
              selectedCommunity: _selectedCommunity,
              onCommunityChanged: (c) => setState(() => _selectedCommunity = c),
              onRespondTap: _openCamera,
              notifController: _notifController,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsible chrome — wraps a block that slides up + fades out on
// scroll-down and slides back down + fades in on scroll-up. Shared by the
// identity-row/pills block (inside _SlimHeader) and the viewer-activity
// toast slot (in HomeScreen.build), so they hide/reveal in lockstep even
// though they live in different parts of the tree. Height animates too
// (not just opacity/offset) so hiding it actually reclaims layout space for
// the feed below, per the "give more room to post content" requirement.
// ---------------------------------------------------------------------------

class _CollapsibleChrome extends StatefulWidget {
  const _CollapsibleChrome({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  @override
  State<_CollapsibleChrome> createState() => _CollapsibleChromeState();
}

class _CollapsibleChromeState extends State<_CollapsibleChrome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.collapsed ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_CollapsibleChrome old) {
    super.didUpdateWidget(old);
    if (old.collapsed != widget.collapsed) {
      _ctrl.animateTo(widget.collapsed ? 1.0 : 0.0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        final t = _ctrl.value;
        final visibleFactor = (1.0 - t).clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: visibleFactor,
            child: Opacity(
              opacity: visibleFactor,
              child: Transform.translate(
                offset: Offset(0, -10 * t),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsing header
// ---------------------------------------------------------------------------

class _SlimHeader extends StatefulWidget {
  const _SlimHeader({
    super.key,
    required this.activeTab,
    required this.topPadding,
    required this.onTabSwitch,
    required this.collapsed,
    required this.bellCollapsed,
    required this.selectedCommunity,
    required this.onCommunityChanged,
    required this.onRespondTap,
    required this.notifController,
  });

  final int activeTab;

  /// MediaQuery's own top safe-area inset — this widget now floats as a
  /// Stack overlay (see HomeScreen.build) rather than sitting after a
  /// sibling SizedBox in a Column, so it has to account for the status bar
  /// itself instead of relying on that sibling for the space.
  final double topPadding;
  final ValueChanged<int> onTabSwitch;

  /// True once the user has scrolled down inside the feed — hides the
  /// identity row + community pills. Flips back to false the instant the
  /// user scrolls up (see HomeScreen._onScrollNotification), independent of
  /// how far down they are.
  final bool collapsed;

  /// The bell/reaction-adder row's OWN collapse state — a plain scroll-
  /// position readout (see HomeScreen._bellCollapsed's own doc), unlike
  /// [collapsed] which starts true on cold start to skip a flash. Visible
  /// at the complete top including the very first frame; hidden once
  /// scrolled past the same threshold.
  final bool bellCollapsed;
  final String selectedCommunity;
  final ValueChanged<String> onCommunityChanged;
  final VoidCallback onRespondTap;

  /// Hosts the merged viewer-activity toast (FeedNotifHost) — pulled in
  /// here (rather than a HomeScreen-level Column sibling, as before) so the
  /// whole floating header, toast included, lives in one self-contained
  /// overlay with a single known top-to-bottom layout, instead of needing
  /// two separately-positioned Stack children to stay visually stacked
  /// while one of them (this widget) is a variable height.
  final FeedNotifController notifController;

  @override
  State<_SlimHeader> createState() => _SlimHeaderState();
}

class _SlimHeaderState extends State<_SlimHeader>
    with TickerProviderStateMixin {
  // "Live" pulse — a subtle glow/scale-breathe on the prompt bar, fires once
  // every 30 seconds. Purely cosmetic: it never touches _dailyPrompt itself,
  // which only ever changes via its own separate (much slower) rotation
  // cycle.
  late final AnimationController _liveCtrl;
  late final Animation<double> _liveAnim;
  Timer? _liveTimer;

  static const _dailyPrompt = "What's something you've never told anyone here?";

  @override
  void initState() {
    super.initState();
    _liveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _liveAnim = CurvedAnimation(parent: _liveCtrl, curve: Curves.easeInOut);
    _fireLivePulse();
    _liveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fireLivePulse(),
    );
  }

  void _fireLivePulse() {
    _liveCtrl.forward(from: 0).then((_) {
      if (mounted) _liveCtrl.reverse();
    });
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  void dispose() {
    _liveCtrl.dispose();
    _liveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, widget.topPadding + 2, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 0: bell (left) + reaction-adder (right) — page-level
            // controls that used to live in MainShell (always pinned,
            // every tab); now scoped to Home's own header (MainShell still
            // renders its own copy on the other 3 tabs — see
            // MainShell.build). Own _CollapsibleChrome keyed off
            // widget.bellCollapsed, NOT widget.collapsed — the latter
            // starts collapsed on cold start to skip a flash (see
            // HomeScreen._chromeCollapsed's own doc), which would hide
            // this row on first load too; bellCollapsed is a plain scroll-
            // position readout instead, so this reads as visible-at-top,
            // hidden-while-scrolled from frame one. No opaque backdrop
            // needed — the self-contained circle treatment reads fine
            // floating over either sub-tab's background.
            _CollapsibleChrome(
              collapsed: widget.bellCollapsed,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    _HeaderBellButton(onTap: _openNotifications),
                    const Spacer(),
                    ReactionLibraryButton(
                      size: 36,
                      onTap: () => openReactionLibrary(
                        context,
                        // Was hardcoded false (always Anonymous scope) —
                        // now reflects whichever sub-tab is actually
                        // active, per explicit correction: "feed_scope
                        // should reflect whichever feed tab is currently
                        // active." widget.activeTab is 0=Anon, 1=Friends
                        // (same field _SlimHeaderState already uses for
                        // its own white/dark background split above).
                        allowFaceReactions: widget.activeTab != 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Stack(
              // Clip.none — this Stack's only non-Positioned child (the
              // toggle row's own _CollapsibleChrome below) is what sizes
              // the Stack, and it shrinks toward zero height once
              // widget.collapsed flips true on scroll. Stack's default
              // clipBehavior is Clip.hardEdge, so the score badge
              // (Positioned top:0/right:0 below, in its OWN separate
              // _CollapsibleChrome keyed off bellCollapsed instead) was
              // being clipped away by the now-tiny Stack bounds at exactly
              // the moment scrolling was supposed to reveal it — the badge
              // widget itself was correctly told "visible", it just had
              // nothing left to paint into. Clip.none lets it paint at its
              // natural position regardless of the sibling's collapsed size.
              clipBehavior: Clip.none,
              children: [
                _CollapsibleChrome(
                  collapsed: widget.collapsed,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Opaque backing behind the logo + switcher — this
                      // block sits above the identity row/pills (which has
                      // always had its own ColoredBox for exactly this
                      // reason) with nothing behind it otherwise, and
                      // AnonymousTab only reserves scroll space for the
                      // status bar now that nothing in this header stays
                      // permanently pinned (see HomeScreen's topInset) — the
                      // header is DELIBERATELY allowed to float over the
                      // feed's first post while expanded. Without an opaque
                      // backing here, that first post's own content shows
                      // straight through every transparent gap in the logo's
                      // shapes and the switcher pill's edges. Matches
                      // Scaffold's own white/dark split so it's invisible in
                      // the non-buggy case.
                      ColoredBox(
                        color: widget.activeTab == 0
                            ? Colors.white
                            : AppColors.background,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "i" wordmark intentionally omitted for now —
                            // see _AppLogoMark below, left in place to
                            // re-add later.

                            // Anon/Friends switcher, truly centered. The
                            // score badge used to sit here too (right-
                            // aligned via a Positioned in this same Stack)
                            // — it's now a separate overlay outside this
                            // whole collapsible block entirely (see the
                            // Stack/Positioned wrapping this
                            // _CollapsibleChrome), since it needs its OWN
                            // visibility rule (hidden on landing, pops in
                            // once scrolling starts) independent of this
                            // row's own scroll-collapse behavior.
                            SizedBox(
                              height: 36,
                              child: Center(
                                child: _FeedToggle(
                                  activeIndex: widget.activeTab,
                                  onToggle: widget.onTabSwitch,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Anon score badge — Anon tab ONLY (it's specifically the
                // viewer's anon-feed score/reputation, not a Friends-feed
                // concept — showing it while on Friends would be
                // contextually wrong even though nothing here previously
                // gated it). Hidden on landing (not shown until the user
                // has scrolled at least a little), then pops in once
                // scrolling starts. Independent of the identity row/toggle
                // above (which follows its own, different collapse rule) —
                // driven by bellCollapsed instead, since that's already a
                // plain "pixels > threshold" readout with no cold-start
                // special-casing, just inverted (bell hides on scroll,
                // score should show on scroll).
                if (widget.activeTab == 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _CollapsibleChrome(
                      collapsed: !widget.bellCollapsed,
                      child: ValueListenableBuilder<int>(
                        valueListenable: ViewerScoreService.instance.score,
                        builder: (context, score, _) =>
                            _HeaderScoreBadge(score: score),
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.activeTab == 0)
              // Prompt composer + viewer-activity toast — pinned, always
              // visible regardless of scroll (unlike the tab switcher/
              // identity row/pills above, which fully hide), but the
              // composer SHRINKS into a genuinely smaller compact form once
              // the feed has scrolled (widget.collapsed), rather than
              // staying full-width/full-height the whole time. `collapsed`
              // is already a plain bool (set from scroll position, see
              // HomeScreen's _onScrollNotification) rather than a continuous
              // scroll offset, so a binary target animated over the same
              // duration as the rest of this collapsible chrome reads as
              // "tied to scroll" without needing its own scroll listener.
              //
              // Two things shrink together, both driven by `collapsed`:
              //  1. Width — via the LayoutBuilder/AnimatedContainer below.
              //  2. The composer's CONTENT ITSELF — via AnimatedCrossFade
              //     in _buildFullComposer swapping in a deliberately
              //     smaller/simpler layout (single-line truncated prompt,
              //     no +vibe/community chips, tighter padding), not the
              //     same content squeezed into less space. AnimatedCrossFade
              //     animates the height change for us, so the container's
              //     size genuinely reduces and reclaims vertical space for
              //     the feed — this is NOT text reflowing inside a
              //     same-size box.
              //
              // LayoutBuilder measures the available (stretched) width
              // first — Align alone can't do this shrink, since the parent
              // Column's crossAxisAlignment.stretch hands every child a
              // TIGHT width, and Align only loosens the constraints it
              // passes to ITS child, it doesn't renegotiate what it itself
              // is given. AnimatedContainer's explicit `width` then only
              // takes effect because it's sitting inside that loosened
              // Align, not directly under the stretch-tight Column.
              ColoredBox(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2), // moved up from 6
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fullWidth = constraints.maxWidth;
                        return Align(
                          alignment: Alignment.center,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: widget.collapsed
                                ? fullWidth * 0.72
                                : fullWidth,
                            child: GestureDetector(
                              onTap: widget.onRespondTap,
                              child: _buildFullComposer(),
                            ),
                          ),
                        );
                      },
                    ),

                    // Viewer-activity toast — collapses in lockstep with the
                    // tab switcher/identity row/pills above (same
                    // `collapsed` bool).
                    _CollapsibleChrome(
                      collapsed: widget.collapsed,
                      child: FeedNotifHost(controller: widget.notifController),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullComposer() {
    return AnimatedBuilder(
      animation: _liveAnim,
      builder: (context, child) {
        final live = _liveAnim.value;
        return Transform.scale(
          scale: 1.0 + 0.012 * live,
          child: DecoratedBox(
            // Soft glow pulse, every 30s (see _fireLivePulse) — purely a
            // "this bar is live" cue, never a hint that the prompt text
            // itself changed (that only ever rotates on its own, much
            // slower cycle).
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: live <= 0
                  ? const []
                  : [
                      BoxShadow(
                        color: AppColors.coral.withValues(alpha: 0.20 * live),
                        blurRadius: 18 * live,
                        spreadRadius: 1 * live,
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
      // AnimatedCrossFade — NOT the same content re-wrapped narrower. The
      // collapsed child is a structurally smaller layout (single-line
      // truncated prompt, no handle-row avatar, no +vibe/community chips,
      // tighter padding), so the height genuinely shrinks and AnimatedSize
      // (built into AnimatedCrossFade) animates that real size change,
      // freeing vertical space for the feed. The expanded child is
      // untouched from before.
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 220),
        sizeCurve: Curves.easeOutCubic,
        firstCurve: Curves.easeOut,
        secondCurve: Curves.easeIn,
        crossFadeState: widget.collapsed
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: _expandedComposerBody(),
        secondChild: _collapsedComposerBody(),
      ),
    );
  }

  // Full-size composer at rest — 12px border radius, roomy padding, full
  // (wrapping) prompt text + Respond button. No handle row (removed —
  // this prompt has no poster identity to show). Measured height ≈ 79px at
  // the current fonts/paddings (~39 two-line prompt + 8 gap + 26 action row
  // + 18 vertical padding — exact height depends on prompt-text wrap, this
  // is content-driven, not a fixed box).
  Widget _expandedComposerBody() {
    return CustomPaint(
      key: const ValueKey('composer-expanded'),
      painter: _DashedBorderPainter(
        color: Colors.black.withValues(alpha: 0.15),
        radius: 12,
        dashWidth: 5,
        dashGap: 5,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            // Glass ribbon: whiter/brighter at the top (a "raised panel"
            // above the base white page), gently warming to a soft cream
            // as it blends toward the post content below — never black.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF6E8)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Prompt text — no handle row above it (the poster's handle
                // was removed; nothing else needs that row's height either).
                Text(
                  _dailyPrompt,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF8A8A8A),
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                // Action row
                Row(
                  children: [
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onRespondTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Respond →',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Collapsed composer — scrolled state. Structurally smaller, not a
  // shrunk-width version of the same content: no handle row, no chips,
  // prompt truncated to one line, tighter padding/radius. Measured height
  // ≈ 40px (8+8 vertical padding + 24 single Row of 20px-tall content) vs
  // ≈116px expanded — a real ~65% height reduction, not just a re-wrap.
  Widget _collapsedComposerBody() {
    return CustomPaint(
      key: const ValueKey('composer-collapsed'),
      painter: _DashedBorderPainter(
        color: Colors.black.withValues(alpha: 0.15),
        radius: 10,
        dashWidth: 4,
        dashGap: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            // Same white -> soft cream ribbon treatment as the expanded
            // state — see _expandedComposerBody's own note.
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF6E8)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF0F0F0),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.person_outline,
                      size: 9,
                      color: Color(0xFF444444),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _dailyPrompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF6A6A6A),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onRespondTap,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header bell + score badge — moved here from MainShell (see MainShell.
// build's own note) so they live inside this feed's own collapsible
// chrome instead of floating permanently above it. Visuals are unchanged
// from the MainShell originals.
// ---------------------------------------------------------------------------

class _HeaderBellButton extends StatelessWidget {
  const _HeaderBellButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalUnread = notifState.totalUnread;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
          if (totalUnread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    totalUnread > 9 ? '9+' : '$totalUnread',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderScoreBadge extends StatelessWidget {
  const _HeaderScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: info.color),
          const SizedBox(width: 5),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: info.color,
            ),
          ),
          // Tier name tag (e.g. "legend") — TierBadge already existed in
          // score_tier.dart but was never actually wired into this header
          // badge, so the badge only ever showed the bare number.
          const SizedBox(width: 6),
          TierBadge(score: score),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed toggle
// ---------------------------------------------------------------------------

class _FeedToggle extends StatelessWidget {
  const _FeedToggle({required this.activeIndex, required this.onToggle});

  final int activeIndex;
  final ValueChanged<int> onToggle;

  static const _labels = ['Anon', 'Friends'];
  static const _width = 152.0;
  static const _height = 34.0;

  @override
  Widget build(BuildContext context) {
    // This toggle is the one piece of chrome always visible regardless of
    // which tab is active, so — unlike everything else in _SlimHeader,
    // which only ever renders against ONE fixed background — it has to
    // read against whichever page background is CURRENTLY showing through
    // it (white behind Anon, black behind Friends).
    final isLight = activeIndex == 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.black.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isLight
                  ? Colors.black.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          // BeReal-style pill: a single sliding highlight behind two fixed
          // label slots, rather than each chip independently cross-fading
          // its own fill (the old _ToggleChip approach) — this is what
          // actually reads as "sliding transition between states" instead
          // of two chips blinking in place. LayoutBuilder measures the
          // REAL available width rather than hand-computing it from _width
          // minus padding/border — Container's border insets eat a couple
          // more px than the explicit padding alone accounts for, which a
          // hardcoded guess silently overflowed by.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chipWidth = constraints.maxWidth / 2;
              return Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: activeIndex == 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      width: chipWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1306C).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFE1306C,
                            ).withValues(alpha: 0.45),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(2, (i) {
                      final active = activeIndex == i;
                      return SizedBox(
                        width: chipWidth,
                        height: double.infinity,
                        child: GestureDetector(
                          onTap: () => onToggle(i),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                // The active label sits on the pink pill
                                // (high-contrast regardless of page
                                // background) — only the inactive label's
                                // color needs to flip per background.
                                color: active
                                    ? Colors.white
                                    : (isLight ? Colors.black : Colors.white)
                                          .withValues(alpha: 0.55),
                              ),
                              child: Text(_labels[i]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App wordmark — stylized lowercase "i": a solid dot sitting on thin
// horizontal rule lines (like music-staff lines), with a bold stem below.
// Sits centered above the Anon/Friends switcher. Built from plain shapes
// rather than a custom glyph/font, so it stays crisp at any size and needs
// no font asset.
// ---------------------------------------------------------------------------

class _AppLogoMark extends StatelessWidget {
  const _AppLogoMark();

  static const double size = 30;

  @override
  Widget build(BuildContext context) {
    const markColor = Color(0xFF1A1A1A);
    const lineWidth = size * 1.15;
    const dotSize = size * 0.3;
    const stemWidth = size * 0.16;
    const stemHeight = size * 0.5;

    return SizedBox(
      width: lineWidth,
      height: size,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Three thin staff-style rule lines, evenly spaced.
          Positioned(
            top: 0,
            child: _staffLine(lineWidth, markColor),
          ),
          Positioned(
            top: size * 0.13,
            child: _staffLine(lineWidth, markColor),
          ),
          Positioned(
            top: size * 0.26,
            child: _staffLine(lineWidth, markColor),
          ),
          // The dot — sits on the middle line, like a note on a staff.
          Positioned(
            top: size * 0.06,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: const BoxDecoration(
                color: markColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Bold stem, below the lines.
          Positioned(
            top: size * 0.42,
            child: Container(
              width: stemWidth,
              height: stemHeight,
              decoration: BoxDecoration(
                color: markColor,
                borderRadius: BorderRadius.circular(stemWidth * 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staffLine(double width, Color color) {
    return Container(width: width, height: 1, color: color.withValues(alpha: 0.3));
  }
}

// ---------------------------------------------------------------------------
// Dashed border painter
// ---------------------------------------------------------------------------

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rect);
    final pathMetrics = path.computeMetrics();

    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dashWidth != dashWidth ||
      old.dashGap != dashGap;
}
