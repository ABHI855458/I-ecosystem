import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../shared/slight_swipe_settle.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../features/profile_v2/my_profile_screen.dart' show openCreateChooser;
import '../../features/profile_v2/profile_v2_icons.dart' show PV2Icons;
import '../../services/daily_prompt_service.dart';
import '../../screens/feed/everyone_feed_screen.dart';
import '../../screens/feed/widgets/post_card_shared.dart'
    show ReactionLibraryButton, openReactionLibrary;
import '../../shared/feed_notif_bar.dart';
import '../../shared/score_tier.dart';
import '../composer/composer_screen.dart';
import 'anon_feed_v2/anon_feed_screen.dart';
import 'anon_feed_v2/anon_feed_tokens.dart';

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------


/// Deep-link request for Home's inner tab: 0 = Dip (anonymous), 1 = Friends.
/// Set by MainShell when a notification should land on a specific side;
/// HomeScreen consumes it and resets it to null.
final ValueNotifier<int?> homeTabRequest = ValueNotifier<int?>(null);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenCamera,
    this.onAnonActiveChanged,
    this.onCommentsOpenChanged,
    this.onFriendsOverscrollUpdate,
    this.onFriendsOverscrollEnd,
    this.debugInitialTab,
  });

  /// Takes the prompt being answered, when the camera is opened from a
  /// prompt bar rather than the plain camera button — plus which community
  /// and `daily_prompts` row that prompt came from, so the resulting post
  /// can be attributed without an extra manual picker step.
  final void Function([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ])? onOpenCamera;
  final int? debugInitialTab;

  /// Fired continuously (including with 0) while sitting on the Friends/
  /// Everyone page (this screen's own inner PageView's last page) with the
  /// raw, undamped pixel amount the drag has pulled past that boundary —
  /// MainShell mirrors this 1:1 onto its outer tab-swipe PageController via
  /// jumpTo so the outer Ping page visually tracks the finger in real time,
  /// instead of only reacting once the gesture ends (which was the cause of
  /// the old two-stage/hitchy transition).
  final ValueChanged<double>? onFriendsOverscrollUpdate;

  /// Fired once the drag that produced [onFriendsOverscrollUpdate] ends —
  /// MainShell decides commit-to-Ping vs spring-back-to-Friends from the
  /// last value it was given.
  final VoidCallback? onFriendsOverscrollEnd;

  /// Fired whenever the Anonymous vs Everyone/Friends sub-page (this
  /// screen's own horizontal PageView) changes — MainShell uses this to
  /// decide the floating tab bar's vertical position (Anonymous keeps its
  /// original floating spot; every other page sits lower, Instagram-style).
  final ValueChanged<bool>? onAnonActiveChanged;

  /// Bubbled straight from AnonFeedScreenV2's own onCommentsOpenChanged —
  /// see that widget's doc for why the tab bar can't just paint over the
  /// comments sheet on its own.
  final ValueChanged<bool>? onCommentsOpenChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Friends first (explicit request: "first let there be friends feed then
  // anon feed") — Home now lands on the Everyone/Friends page (index 1) by
  // default; Dip (0) is still there, one swipe/toggle-tap away. Internal
  // numbering is unchanged (0 = Dip, 1 = Friends — see homeTabRequest's own
  // doc), so every existing `_tabIndex == 0` check below still means Dip.
  late final _pageController =
      PageController(initialPage: widget.debugInitialTab ?? 1);
  final _notifController = FeedNotifController();
  int _tabIndex = 1;
  // Starts COMPACT, not expanded — a bare "at rest at pixels<=0" check
  // can't tell "just loaded, never scrolled" apart from "scrolled down
  // then explicitly back up to the top", and per _onScrollNotification's
  // own rule those two cases would otherwise both read as "expand". Only
  // the second one should — see _hasScrolledPastThreshold below, which
  // gates that re-expand until a real scroll-down has actually happened.
  bool _chromeCollapsed = true;

  /// Combined score of the author of the anon post currently on screen —
  /// reported up by AnonFeedScreenV2. The header badge used to render the
  /// VIEWER's own score on every post, which told you nothing about the
  /// post you were looking at.
  int _activeAuthorScore = 0;

  // Bell + reaction-adder row's own collapse state — deliberately NOT
  // _chromeCollapsed. That flag starts collapsed=true on cold start (see
  // its own doc above) specifically to skip a flash of the identity-row/
  // pills; the bell/plus row has no such flash to avoid, so it should just
  // track raw scroll position from frame one — visible at the complete
  // top (including on first load, pixels==0), hidden once scrolled past
  // the same threshold below.
  bool _bellCollapsed = false;
  bool _hasScrolledPastThreshold = false;
  String _selectedCommunity = 'All';

  // (no per-drag boolean needed any more — see _onScrollNotification's
  // horizontal branch, which now recomputes the live overscroll amount
  // fresh from metrics.pixels/maxScrollExtent on every tick instead of
  // latching a one-shot flag.)

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
    if (widget.debugInitialTab != null) _tabIndex = widget.debugInitialTab!;
    // Landing on Friends (the default since 2026-09-30): open with the
    // header EXPANDED, exactly as switching to Friends does (_switchTab).
    // It used to start collapsed, and _headerExpandedHeight was only ever
    // measured on a switch — so a cold start on Friends reserved the
    // guessed (topPadding + 200) instead, a big empty band above the
    // first post with no Dip/Friends toggle showing.
    if (_tabIndex == 1) _chromeCollapsed = false;
    _updateNotifSuppression();
    // BUG FIX (repeat report — "tab bar again and again overlapping the
    // peek prompt"): every OTHER _tabIndex change (the toggle-pill tap in
    // _switchTab, the inner PageView's own onPageChanged) already calls
    // widget.onAnonActiveChanged — this initial one never did. MainShell's
    // _isHomeAnonActive starts hardcoded to `true` and this screen's own
    // _tabIndex starts at 0 (also Anon), so the two usually agree by
    // coincidence — except when widget.debugInitialTab lands this screen
    // on Friends (or any future path that changes the initial tab), which
    // silently left MainShell's flag on its stale default. MainShell then
    // renders the tab bar at its LOWER, non-Anon position while this
    // screen is actually showing Anon content underneath it — exactly the
    // overlap being reported. One authoritative call here, matching
    // whatever _tabIndex actually resolved to above, closes the gap.
    //
    // Deferred to a post-frame callback: this initState runs while
    // MainShell is still building ITS OWN first frame (HomeScreen is
    // constructed inside MainShell's own initState, as one of its
    // _screens) — calling MainShell's setState synchronously from here
    // hits "setState() or markNeedsBuild() called during build" the
    // instant this screen mounts. Every other call site (the toggle-pill
    // tap, the inner PageView's onPageChanged) fires later, well outside
    // any build phase, which is why only this one needed deferring.
    homeTabRequest.addListener(_onHomeTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAnonActiveChanged?.call(_tabIndex == 0);
      if (widget.debugInitialTab != null) _pageController.jumpToPage(widget.debugInitialTab!);
      final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && mounted) {
        setState(() => _headerBaselineHeight = box.size.height);
      }
      // See the Friends-landing note above — measure the real header now
      // rather than waiting for a tab switch that may never come.
      if (_tabIndex == 1) _captureExpandedHeightOnce();
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
    homeTabRequest.removeListener(_onHomeTabRequested);
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

  void _onHomeTabRequested() {
    final i = homeTabRequest.value;
    if (i == null) return;
    homeTabRequest.value = null;
    if (mounted) _switchTab(i);
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

  void _openCamera([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ]) {
    if (widget.onOpenCamera != null) {
      widget.onOpenCamera!(answeringPrompt, answeringCommunityId, answeringPromptId);
    } else {
      // Fallback only (widget.onOpenCamera is set by MainShell in the real
      // app, which already accounts for the active tab itself) — kept
      // consistent with that path rather than always defaulting Everyone.
      Navigator.of(context).push(openCameraRoute(
        isAnonymous: _tabIndex == 0,
        answeringPrompt: answeringPrompt,
        answeringCommunityId: answeringCommunityId,
        answeringPromptId: answeringPromptId,
      ));
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

  /// Multiplier undoing BouncingScrollPhysics' overscroll friction, so the
  /// Friends→Ping bridge tracks the finger instead of lagging far behind
  /// it. Empirically the iOS damping leaves roughly a third of the real
  /// movement at the distances this bridge cares about.
  static const double _kOverscrollGain = 2.8;

  /// [tab] is the index of the page that OWNS the scrollable this came
  /// from (see _TabScrollScope). Notifications from the page you're not
  /// looking at are dropped — the inactive page keeps its scroll position
  /// and keeps reporting it, which is exactly what used to re-collapse the
  /// header right after a tab switch expanded it.
  bool _onScrollNotification(int tab, ScrollNotification notification) {
    if (tab != _tabIndex) return false;
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

    // Pull-down-to-camera removed: the camera never opens on its own
    // (explicit request) — only from the camera button.
    return false;
  }

  /// The Friends→Ping boundary bridge — split out from
  /// [_onScrollNotification] and wired to a NotificationListener wrapping
  /// the PageView itself, not the per-page _TabScrollScope ones.
  ///
  /// BUG FOUND while chasing "swiping from friends feed to ping page isn't
  /// happening": this bridge logic (onFriendsOverscrollUpdate/End) had been
  /// dead since the PageView's own outer NotificationListener was removed
  /// (see the "No NotificationListener around the whole PageView any more"
  /// comment above, on _TabScrollScope's own fix for a DIFFERENT bug —
  /// stale vertical notifications from the inactive page). That removal
  /// was correct for vertical scroll notifications, but it also meant
  /// nothing was left ABOVE the PageView to see the PageView's OWN
  /// horizontal drag notifications — a NotificationListener only sees
  /// notifications bubbling up from ITS OWN descendants, and _TabScrollScope
  /// sits INSIDE the PageView's children, not around the PageView itself.
  /// The horizontal branch this method now holds was accordingly
  /// unreachable at its old call site — every "you're dragging past
  /// Friends" tick was silently discarded.
  ///
  /// Restoring this as its own OUTER listener (rather than re-adding the
  /// single shared one that caused the original bug) keeps the two fixes
  /// independent: this only ever looks at Axis.horizontal notifications,
  /// which a vertical feed's own ListView never produces, so it cannot
  /// resurrect the stale-vertical-notification bug the removal fixed.
  bool _onPageViewNotification(ScrollNotification notification) {
    // depth == 0: only THIS PageView's own drag. A post's photo carousel
    // (a nested horizontal PageView) bubbles its notifications up here too,
    // and its overscroll past the last photo was read as "swiping off the
    // Friends page" — the page jumped to Ping instead of the card moving.
    // The pager is reversed (Friends left, Dip right), so the page next to
    // Ping is now DIP (index 0), and swiping past it is an overscroll
    // below minScrollExtent.
    if (notification.metrics.axis == Axis.horizontal &&
        notification.depth == 0 &&
        _tabIndex == 0) {
      if (notification is OverscrollNotification ||
          notification is ScrollUpdateNotification) {
        final over = notification.metrics.minScrollExtent -
            notification.metrics.pixels;
        // Un-damped before it's reported. BouncingScrollPhysics applies
        // heavy friction past the edge, so `over` is a small fraction of
        // how far the finger actually travelled — the outer Ping page
        // crawled while the finger moved, and reaching the commit
        // threshold took an unreasonable drag. Reported as "swiping from
        // friends to ping is difficult". _kOverscrollGain restores roughly
        // 1:1 finger tracking.
        widget.onFriendsOverscrollUpdate
            ?.call(over > 0 ? over * _kOverscrollGain : 0);
      }
      if (notification is ScrollEndNotification) {
        widget.onFriendsOverscrollEnd?.call();
      }
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
      // Always black now — the old "Anonymous = white" backdrop is stale:
      // AnonFeedScreenV2 (the current Anon page) already paints its own
      // solid dark ColoredBox(AnonFeedColors.screenBg) over the full
      // screen, so this Scaffold-level color was never actually visible
      // except during a PageView drag — _tabIndex only updates on
      // onPageChanged (page-settle), so mid-swipe this backdrop lagged a
      // frame behind and the white flashed through at the page edges.
      backgroundColor: AppColors.background,
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
            // No NotificationListener around the whole PageView any more.
            // Both pages stay alive across a horizontal swipe, so a single
            // listener here couldn't tell WHICH page a vertical scroll
            // notification came from: a scrolled-down Anon feed kept
            // emitting its own offset after you swiped to Friends, which
            // re-collapsed the chrome (and with it the Anon/Friends pill)
            // a frame after onPageChanged had just expanded it — the
            // reported "Friends pill isn't visible when I scroll anon then
            // swipe over". Each page now reports under its own index and
            // _onScrollNotification ignores whichever one isn't active.
            //
            // This OUTER listener is back, but scoped to the PageView's own
            // horizontal notifications only (see _onPageViewNotification's
            // own doc) — the Friends→Ping bridge needs an ancestor of the
            // PageView to see its scroll events at all, which nothing was
            // providing after the listener above was removed.
            child: NotificationListener<ScrollNotification>(
              onNotification: _onPageViewNotification,
              child: PageView(
                controller: _pageController,
                // Explicit request: "even a slight swipe shall move the
                // page." Stock PageScrollPhysics only commits the turn
                // past the halfway point, or on a release velocity above
                // its own tolerance — a short, slow drag springs back,
                // which read as the swipe being ignored.
                physics: const _SlightSwipePageScrollPhysics(),
                // Friends first, then Dip: reversed lays page 1 (Friends)
                // out on the LEFT and page 0 (Dip) on the right, so the
                // swipe order is Friends → Dip → Ping. Indices are
                // unchanged (0 = Dip, 1 = Friends) everywhere else.
                reverse: true,
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
                  // _headerBaselineHeight is null for exactly the first
                  // frame (it's set from initState's addPostFrameCallback,
                  // one frame after this first builds) — landing directly
                  // on this tab used to paint that ENTIRE first frame with
                  // the hand-estimated (topPadding + 96) fallback instead of
                  // the real measured height. Since this is a single fixed-
                  // height page, a wrong topInset shifts its bottom peek/
                  // prompt block down under the tab bar for that one frame
                  // — imperceptible as a layout value, but the reported
                  // symptom ("tab bar covers the peeking prompt on cold
                  // landing, fixed after navigating away and back") is
                  // exactly that one wrong frame catching a screenshot/
                  // glance before the very next frame silently corrects it.
                  // A same-color placeholder for that single frame (instead
                  // of ever painting the feed with a guessed inset) removes
                  // the bad frame entirely rather than trying to guess it
                  // more accurately.
                  if (_headerBaselineHeight == null)
                    const ColoredBox(color: AnonFeedColors.screenBg)
                  else
                    _TabScrollScope(
                      tab: 0,
                      onNotification: _onScrollNotification,
                      child: AnonFeedScreenV2(
                      topInset: _headerBaselineHeight!,
                      // Wires this screen's own "Friends" toggle chip to the
                      // SAME real tab-switch mechanism _SlimHeader's
                      // _FeedToggle used to drive for both tabs — see
                      // _switchTab's own doc. _SlimHeader no longer renders
                      // its own toggle on the Anon tab (activeTab == 0); this
                      // screen's header owns that role now.
                      onSwitchToFriends: () => _switchTab(1),
                      onCommentsOpenChanged: widget.onCommentsOpenChanged,
                      // Same entry point as _SlimHeader's own "Respond"
                      // action below (onRespondTap: _openCamera) — the
                      // prompt bar is just another way in.
                      onOpenCamera: _openCamera,
                      onActiveAuthorScoreChanged: (score) {
                        if (score != _activeAuthorScore) {
                          setState(() => _activeAuthorScore = score);
                        }
                      },
                    ),
                  ),
                  _TabScrollScope(
                    tab: 1,
                    onNotification: _onScrollNotification,
                    child: EveryoneFeedScreen(
                    chromeCollapsed: _chromeCollapsed,
                    // Unlike AnonymousTab (frozen compact baseline only —
                    // see that call site's own doc), this reserves whichever
                    // of the header's settled heights currently applies,
                    // since _switchTab/onPageChanged always land here with
                    // the header EXPANDED — a frozen compact-only inset
                    // under-reserves and lets the header cover
                    // WallPreviewStrip. See _headerExpandedHeight's doc.
                    //
                    // THREE states now, not two — _chromeCollapsed==true
                    // used to map straight to _headerBaselineHeight (the
                    // bell/plus row's own height, measured at cold start
                    // when bellCollapsed is still false) regardless of
                    // scroll position, which meant that once a real scroll
                    // pushed _bellCollapsed true too (same 8px threshold,
                    // _onScrollNotification), the bell row had already
                    // hidden itself but this reservation never shrank to
                    // match — a permanent dead gap at the true top of the
                    // screen no amount of scrolling could fill. Added the
                    // _bellCollapsed branch so once BOTH flags are true
                    // (the real "scrolled past threshold" state — they
                    // always flip together past initial cold load, see
                    // _onScrollNotification), the reservation shrinks to
                    // just the safe-area inset instead of staying frozen
                    // at the bell row's height.
                    // CONSTANT now — always the expanded header's height.
                    // Switching between three values as the chrome
                    // collapsed made the feed's own top padding shrink
                    // mid-scroll, sliding every post ~150px under the
                    // finger ("glitching, fluctuating"). The header
                    // collapses OVER the content instead, and since it
                    // re-expands only at the very top — exactly where this
                    // full inset is visible — nothing is ever covered.
                    topInset: _headerExpandedHeight ?? (topPadding + 200),
                    // The "Friends" toggle switches to the real friends
                    // feed (accepted friends OR shared community-audience,
                    // deduped) rather than the everyone/explore feed this
                    // screen renders by default.
                    audience: FeedAudience.friends,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Status-bar scrim ────────────────────────────────────────
          // The feed fills the whole body and the header floats over it
          // (see the Stack note above), so once you scroll, post content
          // travels up THROUGH the status-bar band. With nothing painted
          // there it showed raw card innards — a post's comment composer
          // and the next post's header, clipped into a black strip above
          // the Friends pill. That is the "black strip".
          //
          // The header itself deliberately has no backdrop ("the
          // self-contained circle treatment reads fine floating over
          // either sub-tab's background") and that is still true for the
          // circles; what was missing is cover for the band ABOVE them,
          // which is exactly the height the OS draws its clock into.
          //
          // A fade rather than a hard bar: an opaque block would read as a
          // second app bar and reintroduce the dead gap the topInset
          // comment above describes fixing. Ignores pointers so it can
          // never eat a tap meant for the feed or the bell row.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // Softened: it was SOLID for the top 62% of the band, which read
            // as a black bar cut across whatever photo was scrolling under
            // the clock ("why is black there"). Now a see-through fade —
            // 55% at the very top, clear by the bottom, over a slightly
            // taller band — so content visibly flows up under the status
            // bar while the clock stays legible.
            height: topPadding + 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.55),
                      AppColors.background.withValues(alpha: 0.25),
                      AppColors.background.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
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
              authorScore: _activeAuthorScore,
              selectedCommunity: _selectedCommunity,
              onCommunityChanged: (c) => setState(() => _selectedCommunity = c),
              // Responding to the daily prompt carries that prompt into
              // the composer as the post's peek-bar heading.
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
    this.authorScore = 0,
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

  /// Combined score of the author of the anon post on screen. 0 renders
  /// nothing — see the badge's own guard.
  final int authorScore;
  final String selectedCommunity;
  final ValueChanged<String> onCommunityChanged;
  /// Called with the prompt being answered — text, community id, prompt
  /// id — the header owns all three (_SlimHeaderState._promptBar), so it
  /// hands them over rather than making HomeScreen reach into another
  /// widget's state for them. Same 3-argument shape
  /// AnonFeedScreenV2.onOpenCamera already uses, so both feeds' prompt
  /// bars feed the same camera entry point identically.
  final void Function([
    String? answeringPrompt,
    String? answeringCommunityId,
    String? answeringPromptId,
  ]) onRespondTap;

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

  /// The FRIENDS feed's prompt bar.
  ///
  /// Was a hardcoded constant — one sentence, identical for every user,
  /// every community and every hour of the day. That is why the seeded
  /// library "wasn't showing up in the prompt bar": nothing on this screen
  /// ever asked the server for a prompt. Only the anon feed was wired.
  ///
  /// Now scored server-side per window (prompt_bar_for_user, feed scope
  /// 'everyone') via the SAME PromptBarController the anon feed uses — one
  /// cycling/impression/response-count implementation, not two that could
  /// drift. The fallback below is kept as the offline/failed-fetch text so
  /// the bar is never blank.
  static const _fallbackPrompt =
      "What's something you've never told anyone here?";

  late final PromptBarController _promptBar;

  /// What the bar renders. Server prompt (whichever the 5s cycle has
  /// reached) when there is one, the constant otherwise.
  String get _dailyPrompt => _promptBar.active?.text ?? _fallbackPrompt;

  void _onPromptBarChanged() {
    if (mounted) setState(() {});
  }

  /// Passes the prompt actually on screen — text, community id, prompt id
  /// — to whichever camera entry point is answering it, same as the anon
  /// feed's own _AnonHeader does. Without the id/communityId, a tap here
  /// would post with no `prompt_id`, and the resulting post's response
  /// would never attach to (or count toward) the specific prompt the
  /// person was actually shown.
  void _respond() {
    final active = _promptBar.active;
    widget.onRespondTap(
      _dailyPrompt,
      active != null && active.communityId.isNotEmpty ? active.communityId : null,
      active != null && active.id.isNotEmpty ? active.id : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _liveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _liveAnim = CurvedAnimation(parent: _liveCtrl, curve: Curves.easeInOut);
    _promptBar = PromptBarController(feedScope: 'everyone')
      ..addListener(_onPromptBarChanged);
    unawaited(_promptBar.load());
    _fireLivePulse();
    _liveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fireLivePulse(),
    );
    // Real Anon Score badge (below, Row for activeTab==0) needs a fresh
    // fetch whenever the Anon tab is actually being looked at — cheapest
    // real-data approach without a live subscription, matching how the
    // Ping page's own score refetches on load rather than streaming.
    if (widget.activeTab == 0) ViewerScoreService.instance.refresh();
  }

  void _fireLivePulse() {
    _liveCtrl.forward(from: 0).then((_) {
      if (mounted) _liveCtrl.reverse();
    });
  }

  @override
  void didUpdateWidget(_SlimHeader old) {
    super.didUpdateWidget(old);
    if (widget.activeTab == 0 && old.activeTab != 0) {
      ViewerScoreService.instance.refresh();
    }
  }

  @override
  void dispose() {
    _liveCtrl.dispose();
    _liveTimer?.cancel();
    _promptBar
      ..removeListener(_onPromptBarChanged)
      ..dispose();
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
                // Reduced from 10 — real, non-negative space (not a paint
                // transform or a negative-inset hack, both of which broke
                // badly here: Transform.translate got clipped by
                // _CollapsibleChrome's own internal ClipRect below, and
                // negative EdgeInsets crash outright via Padding's
                // isNonNegative assertion). This recovers part of the gap
                // toward Anon's original tighter spacing safely; closing
                // the rest precisely would need restructuring this and the
                // toggle block into a Stack+Positioned pair, which risks
                // breaking the toggle block's own collapse-to-zero scroll
                // animation (it currently sizes that Stack via its own
                // real, unpositioned height) — not attempted here.
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    // Swapped with MyProfileScreen's own banner (explicit
                    // request): "viewed by / pinned" now lives on the feed
                    // page, and notifications moved to Profile instead —
                    // see MyProfileScreen's own chrome list for the bell's
                    // new home. Self-contained, same drop-in the profile
                    // banner already used it as (own count fetch, own
                    // bottom-sheet) — no extra wiring needed here.
                    // Friends feed: "+" to post (Duo / Group chooser) in
                    // place of the viewed-by eye — explicit request,
                    // 2026-10-01; the "+" left the profile banner for this,
                    // and the eye still lives on the profile banner. The
                    // Dip (anon) tab keeps the eye.
                    // "+" on BOTH tabs now (explicit request, 2026-10-01 —
                    // anon too); the viewed-by eye lives on the profile.
                    GestureDetector(
                        onTap: () => openCreateChooser(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0B1418),
                            border: Border.all(
                              // No glow: the header clips it into a square.
                              color: const Color(0xFF29D3E8),
                              width: 1.4,
                            ),
                          ),
                          child: PV2Icons.plus(18, const Color(0xFF29D3E8)),
                        ),
                      ),
                    const Spacer(),
                    ReactionLibraryButton(
                      // 36 -> 40, matching ViewedByBannerButton's ChromeButton
                      // on the other end of this row. They read as a pair and
                      // were visibly different sizes.
                      size: 40,
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
                // Now ALWAYS mounted (both tabs) — the toggle pill inside
                // must be a single persistent instance so it survives a
                // tab switch instead of being destroyed/recreated (that's
                // what makes a real slide transition possible). Previously
                // this whole block was gated to Friends only, for a real,
                // separate reason: widget.collapsed reads scroll
                // notifications bubbling up from AnonFeedScreenV2's
                // PageView (paged, not continuous), whose `pixels` don't
                // mean what this collapse math expects — feeding that
                // straight in produced a bogus mid-collapse heightFactor
                // and a stray white flash while swiping between POSTS on
                // the Anon tab. Fixed at the source instead of by removing
                // the widget: force collapsed:false whenever the Anon tab
                // is active (this block was always fully visible there
                // anyway — Anon never had its own scroll-collapse behavior
                // for the pill), so the buggy signal never reaches it.
                _CollapsibleChrome(
                  collapsed: widget.activeTab == 0 ? false : widget.collapsed,
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
                      //
                      // Always AppColors.background now, even on the Anon
                      // tab: this block's toggle is gated to `activeTab !=
                      // 0` (AnonFeedScreenV2 renders its own toggle instead
                      // — see that gating below), so on the Anon tab this
                      // ColoredBox backs an empty/near-zero-height child.
                      // The old `Colors.white` branch was sized to match
                      // AnonymousTab's white page background, which no
                      // longer applies — AnonFeedScreenV2 is dark — and was
                      // showing through as a stray white bar above its
                      // header.
                      // BUG FIX (explicit report, with a screenshot of the
                      // Friends tab): a flat ColoredBox has a hard-edged
                      // bottom, and that edge sat flush against the feed
                      // scrolling underneath it — visible as a distinct
                      // horizontal black strip right along the toggle pill.
                      // Can't just fade the whole block: the pill itself
                      // still needs a fully OPAQUE backing directly behind
                      // it (that's this box's original purpose — see the
                      // doc below on why a transparent gap here shows the
                      // feed straight through the pill/logo shapes). So the
                      // gradient stays solid through 85% of the height
                      // (comfortably past the pill, which sits well within
                      // that span) and only fades over the final 15% — the
                      // trailing SizedBox gap below the pill, which never
                      // had real content needing a backing anyway.
                      // BUG FIX ("why is there a line below the Friends
                      // pill, blend it" — screenshot showed a thin but
                      // still-visible seam): the original two-stop fade
                      // (opaque -> transparent, in one straight ramp over
                      // the final 15%) is a linear ALPHA ramp, but human
                      // contrast perception isn't linear — the first
                      // portion of any straight fade reads as a comparatively
                      // sharp edge even though the math is smooth. Same
                      // total space (still solid through 85%, still fully
                      // gone by 100%, the pill's own backing is untouched),
                      // just an added mid-stop at 70% opacity so the curve
                      // eases in before dropping the rest of the way,
                      // rather than starting the drop at full contrast.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.background,
                              AppColors.background,
                              AppColors.background.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.85, 0.93, 1],
                          ),
                        ),
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
                            //
                            // SINGLE persistent instance now (both tabs) —
                            // _SlimHeader sits in the shell's own Stack
                            // ABOVE the PageView (home_screen.dart's own
                            // Positioned, not per-page content), so this
                            // widget is never destroyed/recreated when
                            // swiping between Anon and Friends. Previously
                            // duplicated (a second copy lived in
                            // AnonFeedScreenV2's own _AnonHeader) — that
                            // copy is now just a same-height SizedBox
                            // spacer (see _AnonHeader's own doc), so this
                            // is the ONLY place AnonFriendsTogglePill is
                            // built. Fixes two real bugs the duplication
                            // caused: the pill hard-jumping instead of
                            // sliding on switch (AnimatedSwitcher was
                            // cross-fading between two separate widget
                            // instances, not morphing one), and the two
                            // copies drifting to different vertical
                            // positions (each computed its own offset via
                            // a different, independently hand-tuned
                            // formula).
                            // Extra top padding when widget.bellCollapsed —
                            // that's exactly when _AnonHeaderRankBadge
                            // ("230 PROMINENT") takes over the bell's old
                            // top-left corner (see that Positioned's own
                            // doc, a few lines below in this same Stack).
                            // FIXED 36 (not *scale) — the badge's own
                            // height is a literal, unscaled 26 (see
                            // _AnonHeaderRankBadge's Container), so a
                            // scaled offset (previously 24*scale, ~14px on
                            // this device) could land smaller than the
                            // badge itself and still fail to clear it.
                            // Confirmed via screenshot+pixel measurement:
                            // the two were STILL overlapping — badge and
                            // pill sat on the same row, colliding
                            // horizontally (badge's right edge crossed 31px
                            // into the pill's own left edge), not just
                            // vertically close. 36 = 26 (badge height) + 10
                            // gap, comfortably pushes the pill to a
                            // separate row below the badge so the
                            // horizontal collision no longer matters.
                            Padding(
                              padding: EdgeInsets.fromLTRB(40 * anonScale(context), widget.bellCollapsed ? 36.0 : 0, 40 * anonScale(context), 0),
                              child: Center(
                                child: AnonFriendsTogglePill(
                                  scale: anonScale(context),
                                  activeIndex: widget.activeTab,
                                  onToggle: widget.onTabSwitch,
                                ),
                              ),
                            ),
                            // 14 -> 6 — reduces the gap between the pill
                            // and the first post card below it (Friends
                            // tab) / prompt bar (Anon tab), per explicit
                            // request that it read as too much empty space.
                            SizedBox(height: 6 * anonScale(context)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Anon score/rank — Anon tab ONLY. Hidden on landing, pops
                // in once scrolling starts (bellCollapsed inverted: the
                // bell itself hides on scroll, per Row 0's own
                // _CollapsibleChrome above, so this takes over the exact
                // same top-left corner the bell just vacated — no overlap,
                // it's a handoff between two things that are never both
                // visible at once).
                if (widget.activeTab == 0)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: _CollapsibleChrome(
                      collapsed: !widget.bellCollapsed,
                      // The POST AUTHOR's score, not the viewer's. This was
                      // a ValueListenableBuilder on ViewerScoreService — so
                      // every post in the feed wore the same number, your
                      // own. Hidden entirely at 0 (no bare zero, and a
                      // just-loaded feed has no author yet).
                      //
                      // On the ANON feed this is now always 0 by design:
                      // posts_feed NULLs author_total_score for anonymous
                      // rows because an exact score de-anonymized the
                      // author (see AnonFeedPost.authorScore's own doc and
                      // 20260921030000_posts_feed_anon_score_fingerprint).
                      // So this branch is what deliberately removes the
                      // badge there — it is not a missing feature.
                      child: widget.authorScore <= 0
                          ? const SizedBox.shrink()
                          : _AnonHeaderRankBadge(score: widget.authorScore),
                    ),
                  ),
              ],
            ),
            // The old prompt composer + viewer-activity toast block that
            // used to render here (Anon tab only) is removed — superseded
            // by AnonFeedScreenV2's own §4.2 prompt bar, which is now the
            // real one. The viewer-activity toast (FeedNotifHost) that
            // lived alongside it has no replacement yet — a known,
            // explicitly-flagged gap (see AnonFeedScreenV2's own doc on
            // widget.onSwitchToFriends and the earlier decision to proceed
            // without it for now).
          ],
        ),
      ),
    );
  }

  // Retained for a future expanded-composer surface; nothing builds it
  // today. See this file's own history — deliberately not deleted.
  // ignore: unused_element
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
                      onTap: _respond,
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
                  onTap: _respond,
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

// Anon tab's own rank/score badge, restyled to match AnonFeedScreenV2's
// design language (spec §2's palette/type tokens) instead of the generic
// dark-chip look the rest of this file's chrome uses — same
// peekBg/hairline/star treatment as the peek panel's own "★ 512 TRUSTED"
// row (anon_feed_screen.dart's _AnonBottomBlock), since this badge shows
// the same kind of score+tier information for the SAME feed.
class _AnonHeaderRankBadge extends StatelessWidget {
  const _AnonHeaderRankBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final info = tierInfoForScore(score);
    // Smaller than the first pass (explicit request) — this sits right in
    // the bell's own corner, not inside the feed body, so it doesn't need
    // the peek panel's more legible sizing.
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AnonFeedColors.peekBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AnonFeedColors.hairlineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 11, color: AnonFeedColors.accentCyan),
          const SizedBox(width: 4),
          Text(
            '$score',
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 11, fontWeight: FontWeight.w800, color: AnonFeedColors.textPeek),
          ),
          const SizedBox(width: 4),
          Text(
            info.title.toUpperCase(),
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AnonFeedColors.textDim),
          ),
        ],
      ),
    );
  }
}

// Feed toggle — removed. The old pink BeReal-style sliding pill
// (_FeedToggle) has been replaced by AnonFriendsTogglePill
// (anon_feed_v2/anon_feed_screen.dart), the SAME pill AnonFeedScreenV2
// renders on its own side, per explicit request that both tabs show one
// identical toggle rather than two separately-designed ones.

// ---------------------------------------------------------------------------
// App wordmark — stylized lowercase "i": a solid dot sitting on thin
// horizontal rule lines (like music-staff lines), with a bold stem below.
// Sits centered above the Anon/Friends switcher. Built from plain shapes
// rather than a custom glyph/font, so it stays crisp at any size and needs
// no font asset.
// ---------------------------------------------------------------------------

// Kept for the wordmark that is intentionally omitted from the header for
// now (see the header's own comment). Unreferenced until it returns.
// ignore: unused_element
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


// ---------------------------------------------------------------------------
// Tags every vertical scroll notification with the index of the page it
// came from, so HomeScreen can ignore the page that isn't on screen.
// Returns false so the notification keeps bubbling — this observes, it
// never consumes.
// ---------------------------------------------------------------------------

class _TabScrollScope extends StatelessWidget {
  const _TabScrollScope({
    required this.tab,
    required this.onNotification,
    required this.child,
  });

  final int tab;
  final bool Function(int tab, ScrollNotification notification) onNotification;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) => onNotification(tab, n),
      child: child,
    );
  }
}

/// Page physics that commit the turn on a short swipe.
///
/// [PageScrollPhysics] decides where to land by rounding the fractional
/// page, nudged half a page in the fling direction only when the release
/// velocity clears `toleranceFor(position).velocity`. A brief, gentle
/// drag clears neither, so it snaps back to where it started. Lowering
/// both the fling thresholds and that velocity tolerance means any drag
/// still moving when the finger lifts carries the page across — while a
/// completely static touch-and-release (velocity 0) still doesn't, so
/// resting a thumb on the screen never navigates.
class _SlightSwipePageScrollPhysics extends PageScrollPhysics
    with SlightSwipeSettle {
  const _SlightSwipePageScrollPhysics({super.parent});

  @override
  _SlightSwipePageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SlightSwipePageScrollPhysics(parent: buildParent(ancestor));

  @override
  double get minFlingVelocity => 8; // default 50
  @override
  double get minFlingDistance => 2; // default 18

}
