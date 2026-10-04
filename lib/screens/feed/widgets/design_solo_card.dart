import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/composer/dual_photo_compositor.dart'
    show kFriendsPostRadius, kPostRailButtonSize;
import '../../../features/moderation/post_actions_menu.dart';
import '../../../services/current_user_service.dart';
import '../../../services/post_size_prefs_service.dart';

import 'package:flutter/services.dart' show HapticFeedback;
import '../../../core/glass.dart';
import '../../../services/ping_service.dart';
import '../../../features/profile_v2/profile_navigation.dart';
import '../../../features/profile_v2/duo_highlights.dart' show openDuoAlbumBetween;
import '../../../features/profile_v2/profile_v2_icons.dart';
import '../../../services/post_author_pin_service.dart';
import '../../../services/post_service.dart' show PostViewer, PostService;
import '../../../services/presence_service.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import 'post_card_shared.dart';
import 'dual_photo_view.dart';
import 'post_photo_carousel.dart';

// ---------------------------------------------------------------------------
// DesignSoloCard — a pixel-faithful port of the SOLO CARD section of the
// live Claude Design file (Feed.dc.html, project "Postcard feed design
// layout"), replacing PersonalPostCard/PostCard (post_card.dart)'s
// dual-camera design per explicit request: the design's exact layout,
// wired to this app's real backend (ReactionService/RealmojiService/
// CommentService via the PostReactions mixin + PostCommentCard, both
// already real and unchanged here).
//
// Real-data gaps, handled by omission rather than fabrication:
//  - No verified-user column exists anywhere in the schema/query — the
//    verified badge never renders (always false), instead of faking it.
//  - No second (front-camera) photo is ever actually wired to any real
//    post today (PersonalPostCard's own frontPhoto param was never passed
//    at its call site) — there is no PiP inset here at all.
//  - Live presence stays the existing demoLivePresence(postId) placeholder
//    (deterministic, not random) — real Supabase Realtime presence is
//    explicitly future work.
//  - Ping has no real persistence backend anywhere in this app (grepped:
//    no PingService, no `pings` table write even in the existing
//    ping_prompt_sheet.dart) — tapping a prompt here closes the dropdown
//    and shows a toast, exactly as "real" as the sheet it replaces.
//  - Block/Report have no backend wired to a post id anywhere in this
//    codebase — the more-menu is UI-only (no-op), not faked.
// ---------------------------------------------------------------------------

class DesignSoloCard extends StatefulWidget {
  const DesignSoloCard({
    super.key,
    required this.postId,
    required this.username,
    required this.userId,
    this.avatarUrl,
    this.partnerUserId,
    this.partnerName,
    this.partnerAvatarUrl,
    this.pairStreak,
    this.viewerSeen = false,
    this.caption,
    this.photoUrl,
    this.photoUrls,
    this.commentCount = 0,
    this.onCommentTap,
    this.onDeleted,
    this.showReactionsViewer = false,
    this.showActionRail = true,
    this.secondaryPhotoUrl,
    this.insetOnRight = true,
    this.photoPath,
    this.aspectRatio,
    this.hideOwnOptionsButton = false,
  });

  /// True on the owner's own profile (MyProfileScreen), which draws its OWN
  /// "..." button (delete, not Block/Report — meaningless on your own post)
  /// as a Positioned overlay at a fixed spot chosen to sit exactly where
  /// this card's own inline button normally lands.
  ///
  /// BUG FIX: that fixed spot assumed a plain single-author header. A
  /// shared (Duo) post's header is wider — the fused avatar plus two
  /// tappable names — so the card's own inline "..." here renders further
  /// along the Row than the profile's fixed overlay expects, and the two no
  /// longer land on the same pixel. Reported as "the us album post under
  /// posts is showing 6 dots" (two separate "⋯" glyphs sitting next to each
  /// other instead of one masking the other). Removing this card's own
  /// button entirely when the caller supplies its own is a real fix rather
  /// than re-guessing new coordinates that would only drift again the next
  /// time the header's content changes width.
  final bool hideOwnOptionsButton;

  /// This post's own stored `posts.aspect_ratio` (FeedItem.aspectRatio) —
  /// the size ITS poster chose at compose time (PostSizePresetPicker).
  /// Parsed with [parseStoredAspectRatio]; never a viewer-side setting —
  /// "only the poster gets to design the post size... who posts, not
  /// [everyone else] in the feed, they don't get to change it."
  final String? aspectRatio;

  /// A just-posted photo still on disk, before its upload finishes.
  ///
  /// The optimistic card built by FeedItem.fromLocalPost carries only this
  /// — no URL exists yet — and this card read URLs ONLY, so a brand-new
  /// post rendered as a caption above an empty frame until the upload
  /// landed. Explicit report, with a screenshot: "the new post shall appear
  /// along with pic only". Now that posting closes the composer
  /// immediately (background upload), that window is exactly when you're
  /// looking at the post.
  final String? photoPath;

  /// The dual photo's un-flattened inset layer (FeedItem.secondaryPhotoUrl)
  /// — null for every ordinary post, which keeps the plain
  /// PostPhotoCarousel. See DualPhotoView's own doc.
  final String? secondaryPhotoUrl;
  final bool insetOnRight;

  /// Item #1 — the public "who reacted" pill/dropdown is gone from every
  /// feed card; this renders PostReactionsSection (author-only "Reactions"
  /// list) instead, in the card's own flow above the comment card. Only
  /// ever true on the post author's own profile (see PostsList).
  final bool showReactionsViewer;

  /// Ping + RealMoji. False on the poster's own profile (item #1 — reacting
  /// to your own post is meaningless there; reacting still happens from the
  /// feed), true everywhere else including someone else's profile.
  final bool showActionRail;

  final String postId;
  final String username;

  /// The SECOND author, for a shared (Duo) post. When set the header
  /// draws a FUSED avatar (the two profile photos overlapped) and both
  /// names instead of one, and a ping from this card goes to both people.
  /// Null on an ordinary post, which renders exactly as before.
  final String? partnerUserId;
  final String? partnerName;
  final String? partnerAvatarUrl;

  /// The pair's ping streak (days) — FeedItem.pairStreak, from
  /// FeedService._attachAuthors' us_post_streaks RPC. Null (not 0) means
  /// "no streak to show", same convention PV2Icons.blueFlameStreak follows.
  final int? pairStreak;

  /// True on a PROFILE screen (own or someone else's), false in a FEED.
  /// Swaps the live "here" pill (post_presence, 3h window) for the "seen"
  /// pill (post_viewers, all-time) — same corner of the same card, same
  /// underlying post. Explicit instruction: "the seen pill ... shall be on
  /// each post the person has done, not on the profile [banner] ... it
  /// replaces the here pill" — this is a per-surface swap, not tied to
  /// [showActionRail]'s own-profile/other-profile distinction, since a
  /// post shown on SOMEONE ELSE'S profile should also read "seen", not
  /// "here" the way it does in the feed.
  final bool viewerSeen;

  bool get isShared => (partnerUserId ?? '').isNotEmpty;


  /// The poster's `users.id` — global profile routing. See
  /// features/profile_v2/profile_navigation.dart.
  final String userId;
  final String? avatarUrl;
  final String? caption;
  final String? photoUrl;

  /// All photos, in display order, for a multi-photo post. Null/empty falls
  /// back to [photoUrl] — see resolvePostPhotos in post_photo_carousel.dart.
  final List<String>? photoUrls;

  final int commentCount;
  /// INTENTIONALLY UNUSED on this card — do not "fix" by wiring it to the
  /// comment row.
  ///
  /// Other cards (EveryonePostCard, TextPostCard, PhotoPostCard) do use it,
  /// which is why the parameter exists and why the feed passes it here too.
  /// This card deliberately opens the inline comments sheet
  /// (showPostCommentsSheet) from its comment row instead, and the whole-card
  /// tap already routes to the post detail screen through SpotlightCard's
  /// onTap. Wiring this as well would replace the inline sheet with a full
  /// screen push — a behaviour change, not a bug fix.
  ///
  /// Kept rather than removed so the call sites stay uniform across card
  /// types. An audit flagged it as a "dead callback"; it is dead on purpose.
  final VoidCallback? onCommentTap;

  /// Fired after the overflow menu's Remove actually deletes this post, so
  /// the host feed can drop the row. Without it the card stayed on screen
  /// after a successful delete until a manual refresh — the feed screen's
  /// own _openPostMenu has always passed this, but the card's internal
  /// menu (the one real posts actually use) never did.
  final VoidCallback? onDeleted;

  @override
  State<DesignSoloCard> createState() => _DesignSoloCardState();
}

class _DesignSoloCardState extends State<DesignSoloCard>
    with PostReactions<DesignSoloCard> {
  List<LikeReactor> _reactors = const [];
  bool _showLiveDropdown = false;
  bool _showMoreMenu = false;
  String? _mySelfieUrl;
  List<PresenceUser> _present = const [];
  /// False until the first [_loadPresence] resolves. Distinguishes "really
  /// nobody's here" from "haven't asked the server yet" — both start as an
  /// empty [_present] list, which otherwise renders as a confident "only
  /// you" pill for one network round-trip and then FLIPS the instant real
  /// presence arrives. Reported as the pill visibly changing right after
  /// landing on the feed. The pill now stays invisible (not a skeleton —
  /// its own size is reserved so nothing else reflows) until this is true.
  bool _presenceLoaded = false;
  List<PostViewer> _viewers = const [];

  /// Multi-photo list when the post has one, else the single cover photo.
  List<String> get _photos => resolvePostPhotos(
    photoUrls: widget.photoUrls,
    singleUrl: widget.photoUrl,
  );

  /// True while this post is still uploading — nothing but a local file to
  /// draw from. See DesignSoloCard.photoPath.
  bool get _isLocalPending =>
      _photos.isEmpty && (widget.photoPath ?? '').isNotEmpty;

  // TapRegion groupId pairing the live trigger with its own panel — a tap
  // on either member doesn't count as "outside" the other, but a tap
  // anywhere else (including elsewhere on this same card, or a different
  // card entirely) does, per spec §C's "outside-tap closes it". Suffixed
  // with postId since many DesignSoloCards are mounted at once in a
  // scrolling feed.
  late final String _liveGroupId = 'live-${widget.postId}';

  ScrollPosition? _scrollPosition;

  /// A pin change re-fetches the seen/"here" list, so an open dropdown's
  /// PINNED section updates immediately (PostAuthorPinService.changes).
  void _onPinsChanged() {
    if (!mounted) return;
    unawaited(widget.viewerSeen ? _loadViewers() : _loadPresence());
  }

  @override
  void initState() {
    super.initState();
    PostAuthorPinService.instance.changes.addListener(_onPinsChanged);
    loadReactionSummary(widget.postId);
    unawaited(loadMyRealmojiReaction(widget.postId));
    unawaited(_loadReactors());
    if (widget.viewerSeen) {
      unawaited(_loadViewers());
    } else {
      // touch() is a HERE-surface concern only — visiting a post on a
      // PROFILE shouldn't mark you as live-present on it, it should just
      // read who has ever seen it.
      unawaited(PresenceService.instance.touch(postId: widget.postId));
      unawaited(_loadPresence());
      // The PERMANENT view record, distinct from the live presence
      // heartbeat above. Only the anon feed ever wrote these, so on a
      // friends post post_views stayed empty forever — which silently
      // disabled both the seen pill AND the "here" pill's pinned-viewer
      // merge (a pinned person who viewed the post is supposed to show
      // there whether or not they're currently around). Deduped and
      // self-view-guarded server-side in record_post_view.
      unawaited(PostService.instance.recordView(widget.postId));
    }
  }

  Future<void> _loadPresence() async {
    final entries = await PresenceService.instance.fetchPresence(postId: widget.postId);
    if (!mounted) return;
    setState(() {
      _present = entries.map(PresenceUser.fromEntry).toList();
      _presenceLoaded = true;
    });
  }

  Future<void> _loadViewers() async {
    final viewers = await PostService.instance.fetchPostViewers(widget.postId);
    if (!mounted) return;
    setState(() => _viewers = viewers);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (newPosition != _scrollPosition) {
      _scrollPosition?.removeListener(_onAncestorScroll);
      _scrollPosition = newPosition;
      _scrollPosition?.addListener(_onAncestorScroll);
    }
  }

  void _onAncestorScroll() {
    if (_showLiveDropdown || _showMoreMenu || showPresetTray) {
      _hideMoreMenuOverlay();
      if (showPresetTray) closePresetTray();
      setState(() {
        _showLiveDropdown = false;
      });
    }
  }

  @override
  void dispose() {
    PostAuthorPinService.instance.changes.removeListener(_onPinsChanged);
    _scrollPosition?.removeListener(_onAncestorScroll);
    _moreMenuEntry?.remove();
    super.dispose();
  }

  Future<void> _loadReactors() async {
    final reactors = await ReactionService.instance.fetchRecentReactors(
      widget.postId,
      limit: 8,
    );
    if (!mounted) return;
    setState(() => _reactors = reactors);
  }

  @override
  Future<void> selectPreset(
    String? postId,
    ReactionPreset preset, {
    String? groupPostId,
  }) async {
    await super.selectPreset(postId, preset, groupPostId: groupPostId);
    unawaited(_refreshMySelfie());
  }

  @override
  Future<void> captureRealmojiAndReact(
    String? postId,
    ReactionPresetCategory category,
    RealmojiType type, {
    String? groupPostId,
  }) async {
    await super.captureRealmojiAndReact(
      postId,
      category,
      type,
      groupPostId: groupPostId,
    );
    unawaited(_refreshMySelfie());
  }

  Future<void> _refreshMySelfie() async {
    final type = myRealmojiReaction;
    if (type == null) {
      setState(() => _mySelfieUrl = null);
      return;
    }
    final url = await RealmojiService.instance.savedSelfieUrl(
      feedScope: ReactionPresetCategory.everyone.wire,
      emojiType: type,
    );
    if (!mounted) return;
    setState(() => _mySelfieUrl = url);
  }

  // Mutual exclusion (spec §C: "only one of each open per card") — every
  // trigger's onTap calls this before opening its own panel, so opening any
  // ONE of live/ping/more/reactions-strip/RealMoji-tray closes every other
  // one. closePresetTray() reaches into the PostReactions mixin's own
  // showPresetTray flag (the RealMoji picker, floated via PostReactionCorner
  // — already has its own correct Overlay-based outside-tap/scroll dismiss,
  // just also needs to close when a DIFFERENT panel opens).
  void _closeAllPanels() {
    _showLiveDropdown = false;
    _showMoreMenu = false;
    if (showPresetTray) closePresetTray();
    _hideMoreMenuOverlay();
  }

  // ---------------------------------------------------------------------
  // More (⋯) menu — a real OverlayEntry, not a local Positioned. The old
  // local Positioned(top:32,right:0) inside a small Stack nested in the
  // HEADER row overflowed via Clip.none, but the CAPTION and PHOTO block
  // are LATER Column siblings that paint AFTER the header — so the
  // overflow was being painted over by them ("hidden behind the post
  // card"). Mirrors PostReactionCorner's own OverlayEntry pattern
  // (post_card_shared.dart) so the menu paints above the entire app, with
  // its own full-screen outside-tap dismiss barrier.
  // ---------------------------------------------------------------------
  final _moreMenuKey = GlobalKey();
  OverlayEntry? _moreMenuEntry;

  void _toggleMoreMenu() {
    if (_moreMenuEntry != null) {
      _hideMoreMenuOverlay();
      return;
    }
    _closeAllPanels();
    final box = _moreMenuKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    if (box == null || overlayState == null) return;
    final topLeft = box.localToGlobal(Offset.zero);

    _moreMenuEntry = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.of(overlayContext).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _hideMoreMenuOverlay,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              right: screen.width - (topLeft.dx + box.size.width),
              top: topLeft.dy + box.size.height + 4,
              child: Material(
                color: Colors.transparent,
                // Both actions were DECORATIVE: they popped a toast saying
                // "Blocked"/"Reported" and wrote nothing anywhere, and
                // Report never asked what the report was for. So the
                // Friends/Everyone feed had no working way to report or
                // block anything, while Anon and Moments did — reported as
                // "the dropdown to report which you give in moments give it
                // everywhere like what type of report".
                //
                // Both now hand off to the shared showPostActionsMenu, the
                // same sheet Moments and the Anon feed use: real
                // ReportService/BlockService calls, a reason step on
                // Report, and Remove instead of Report on your own post.
                child: MoreMenuDropdown(
                  onBlock: () {
                    _hideMoreMenuOverlay();
                    _openRealMenu();
                  },
                  onReport: () {
                    _hideMoreMenuOverlay();
                    _openRealMenu();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_moreMenuEntry!);
    setState(() => _showMoreMenu = true);
  }

  /// The real Remove / Report(+reason) / Block sheet.
  ///
  /// `isOwnPost` is resolved lazily here rather than held in state: this
  /// card is built by the dozen while scrolling, and only the one whose
  /// menu is actually opened needs to know.
  Future<void> _openRealMenu() async {
    String? me;
    try {
      me = await CurrentUserService.instance.resolveId();
    } catch (_) {
      // Signed out — falls through as "not mine", which offers Report
      // rather than Remove. The safe direction.
    }
    if (!mounted) return;
    await showPostActionsMenu(
      context,
      postId: widget.postId,
      isOwnPost: widget.userId.isNotEmpty && widget.userId == me,
      isAnonymousPost: widget.userId.isEmpty,
      authorUsersId: widget.userId.isEmpty ? null : widget.userId,
      onDeleted: widget.onDeleted,
    );
  }

  void _hideMoreMenuOverlay() {
    _moreMenuEntry?.remove();
    _moreMenuEntry = null;
    if (_showMoreMenu) _showMoreMenu = false;
  }

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();
    final hasPhoto = _photos.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- Header: avatar, username, live pill, more menu ----
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => openProfile(context, widget.userId),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      if (widget.isShared)
                        // The pair's faces open their Duo album (anyone);
                        // each name still opens that person's profile.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => openDuoAlbumBetween(
                            context,
                            userA: widget.userId,
                            userB: widget.partnerUserId!,
                            streak: widget.pairStreak ?? 0,
                          ),
                          child: _FusedAvatar(
                            seed: widget.postId,
                            photoUrl: widget.avatarUrl,
                            partnerPhotoUrl: widget.partnerAvatarUrl,
                            pairStreak: widget.pairStreak,
                          ),
                        )
                      else
                        _Avatar(seed: widget.postId, photoUrl: widget.avatarUrl),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // A shared (Duo) post names TWO people, on ONE
                            // line (explicit request; it used to wrap to a
                            // second). Both names always show: the line
                            // scales down to fit, and only a very long name
                            // is shortened on its own — never the partner
                            // dropped behind a single trailing ellipsis.
                            if (widget.isShared)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                // Each name opens ITS person's profile (the
                                // header as a whole still opens the poster).
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => openProfile(context, widget.userId),
                                      child: Text(
                                        _shortName(widget.username),
                                        maxLines: 1,
                                        style: GoogleFonts.nunito(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      ' & ',
                                      style: GoogleFonts.nunito(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: (widget.partnerUserId ?? '').isEmpty
                                          ? null
                                          : () => openProfile(context, widget.partnerUserId!),
                                      child: Text(
                                        _shortName((widget.partnerName ?? '').trim().isEmpty ? 'someone' : widget.partnerName!.trim()),
                                        maxLines: 1,
                                        style: GoogleFonts.nunito(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                widget.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunito(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The Us-post blue flame now lives on the fused avatar itself
              // (see _FusedAvatar's pairStreak param) — explicit
              // instruction: "place the blue flame on the users dp", not
              // floating beside the header as before.
              const SizedBox(width: 10),
              TapRegion(
                groupId: _liveGroupId,
                // maxAvatars/rightPadding trimmed from the pill's 3-face/13pt
                // defaults — this header also carries the username, which
                // needs to fit AppStrings.usernameMaxLength (15 chars)
                // without ellipsis; see this card's own class-level doc for
                // the full byline width budget.
                child: widget.viewerSeen
                    ? SeenPill(
                        viewers: _viewers,
                        maxAvatars: 2,
                        rightPadding: 10,
                        // Faces only on a Duo post, exactly like the feed's
                        // pill for the same post — the two-name byline
                        // needs the width ("like in friends feed, circles").
                        avatarsOnly: widget.isShared,
                        onTap: () {
                          setState(() {
                            final next = !_showLiveDropdown;
                            _closeAllPanels();
                            _showLiveDropdown = next;
                          });
                          if (_showLiveDropdown) unawaited(_loadViewers());
                        },
                      )
                    : Opacity(
                        // See _presenceLoaded's own doc: invisible rather
                        // than absent, so the pill's real size is already
                        // reserved and nothing around it reflows the
                        // instant real data arrives — only the "only you"
                        // -> real-count FLASH is what's being removed.
                        opacity: _presenceLoaded ? 1 : 0,
                        child: LivePresencePill(
                          // Shared (Duo) posts drop the pill's label and
                          // chrome down to just the faces — the byline has
                          // TWO usernames to fit and the words cost more
                          // width than they earn. See LivePresencePill's
                          // avatarsOnly doc.
                          avatarsOnly: widget.isShared,
                          present: _present,
                          maxAvatars: 2,
                          rightPadding: 10,
                          onTap: () {
                            setState(() {
                              final next = !_showLiveDropdown;
                              _closeAllPanels();
                              _showLiveDropdown = next;
                            });
                            if (_showLiveDropdown) unawaited(_loadPresence());
                          },
                        ),
                      ),
              ),
              // See hideOwnOptionsButton's own doc — the caller (a profile
              // screen showing its own posts) draws its own "..." instead.
              if (!widget.hideOwnOptionsButton) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  key: _moreMenuKey,
                  onTap: _toggleMoreMenu,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz, size: 22, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ---- Caption ----
        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              widget.caption!,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: Colors.white,
              ),
            ),
          ),

        // ---- Photo block + overlays ----
        // Item #1: the bottom-left "who reacted" pill/dropdown is gone —
        // relocated to PostReactionsSection, author-only, below (see
        // widget.showReactionsViewer near PostCommentCard).
        if (hasPhoto)
          // Full-bleed: the photo runs edge to edge, rounded on its top
          // corners only, exactly like the reference. The overlays below
          // stay anchored to the photo's own edges, so dropping the old
          // 12pt side padding moves them with it rather than past it.
          //
          // Frame comes from THIS post's own stored aspect_ratio — the
          // poster's compose-time choice, never a viewer preference. See
          // widget.aspectRatio's own doc.
          Builder(
            builder: (context) {
              final aspect = parseStoredAspectRatio(widget.aspectRatio);
              return Stack(
              clipBehavior: Clip.none,
              children: [
                // A dual photo (widget.secondaryPhotoUrl set) gets the
                // interactive live view instead of the carousel — see
                // DualPhotoView's own doc. Everything else (single or
                // multi-photo) is unchanged: same 3:4 frame and gradient
                // scrim either way, so every overlay below keeps its exact
                // position. See post_photo_carousel.dart.
                if (_isLocalPending)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kFriendsPostRadius),
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: Image.file(
                        File(widget.photoPath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else if ((widget.secondaryPhotoUrl ?? '').isNotEmpty && _photos.isNotEmpty)
                  DualPhotoView(
                    backgroundUrl: _photos.first,
                    insetUrl: widget.secondaryPhotoUrl!,
                    insetOnRight: widget.insetOnRight,
                    aspectRatio: aspect,
                  )
                else
                  PostPhotoCarousel(
                    photoUrls: _photos,
                    aspectRatio: aspect,
                    borderRadius: kFriendsPostRadius,
                  ),

                if (_showLiveDropdown)
                  Positioned(
                    top: 10,
                    right: 12,
                    child: TapRegion(
                      groupId: _liveGroupId,
                      onTapOutside: (_) =>
                          setState(() => _showLiveDropdown = false),
                      child: widget.viewerSeen
                          ? SeenDropdown(viewers: _viewers)
                          : LivePresenceDropdown(present: _present),
                    ),
                  ),

                // Right action rail: ping (top) + RealMoji (bottom), gap 22.
                // Hidden on the poster's own profile (showActionRail false)
                // — item #1.
                if (widget.showActionRail)
                  Positioned(right: 13, bottom: 14, child: _actionRail()),

                // Bottom-left: the same reaction preview everywhere now —
                // feed AND profile. Only what happens on tap differs.
                // PROFILE (viewerSeen) opens the comments sheet, reactor
                // strip and all — reactor identity is allowed to show there
                // ("accessible only in the profile page"). FEED points
                // there instead of opening anything: "if they click on the
                // friends feed there shall be a notification like visit
                // their profile to view reactions in post".
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: ReactionPreviewChip(
                    count:
                        reactions.totalEmojiCount + reactions.faceReactions.length,
                    faces: reactions.faceReactions,
              emojiCounts: reactions.emojiCounts,
                    onTap: widget.viewerSeen
                        ? () => showPostCommentsSheet(
                              context,
                              postId: widget.postId,
                              isGroup: false,
                              reactors: _reactors,
                              reactionCount: reactions.totalReactionCount,
                            )
                        : () => showGlassToast(
                              context,
                              'Visit their profile to view reactions in this post',
                            ),
                  ),
                ),
              ],
              );
            },
          )
        else
          // No photo: the rail lost its anchor (it was Positioned inside
          // the photo's own Stack), so it renders inline instead — a
          // caption-only post must not lose Ping/RealMoji just because it
          // has no photo to float them over.
          if (widget.showActionRail)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: _actionRail(),
              ),
            ),

        // The standalone "Reactions" section (PostReactionsSection) is
        // gone — the reaction chip above now opens the comments sheet
        // itself on a profile, which is the single way to view reactions
        // there. widget.showReactionsViewer is no longer read by this
        // card; still accepted for the callers that pass it (Moment cards
        // elsewhere use it independently).
        PostCommentCard(
          postId: widget.postId,
          // Reactor identity only reaches this card's OWN comment-icon
          // sheet on a profile — the feed keeps it out entirely, same rule
          // the reaction chip above follows.
          reactors: widget.viewerSeen ? _reactors : const [],
          reactionCount: reactions.totalReactionCount,
        ),
      ],
    );
  }

  Future<void> _pingAuthor() async {
    HapticFeedback.lightImpact();
    final who = widget.isShared
        ? '${widget.username} & ${(widget.partnerName ?? '').trim().isEmpty ? 'someone' : widget.partnerName!.trim()}'
        : widget.username;
    try {
      await PingService.instance.pingPostAuthor(
        postId: widget.postId,
        prompt: '',
        anonymous: false,
      );
      if (mounted) showGlassToast(context, 'Pinged $who ✓');
    } on Object catch (e) {
      if (!mounted) return;
      showGlassToast(
        context,
        e is PingLimitExceeded ||
                e is PingAlreadyOpen ||
                e is PingSelfNotAllowed ||
                e is PingBlocked
            ? e.toString()
            : "Couldn't send that ping.",
        isError: true,
      );
    }
  }

  /// Ping (top) + RealMoji (bottom), gap 22 — shared by the photo overlay
  /// (Positioned, floated bottom-right on the photo) and the no-photo inline
  /// row, so the two layouts can never drift on which buttons a post gets.
  Widget _actionRail() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Opens the app's original ping sheet (PostReactions.openPing ->
        // showPingPromptSheet), and NOW ACTUALLY SENDS.
        //
        // This button had no onSentPrompt: the sheet opened, you picked a
        // prompt, the sheet closed, and nothing was written anywhere. The
        // personal-post Ping was decorative on every card in the feed.
        //
        // ping_post_author resolves the recipient(s) server-side from the
        // post id, so a shared (Duo) post pings BOTH of its authors —
        // see 20260907180000_ping_both_post_authors.sql. The client does
        // not pick who to ping, which is also why it cannot be tricked into
        // pinging someone who isn't on the post.
        PostPingButton(
          size: kPostRailButtonSize,
          // One tap = pinged, no prompt sheet (user decision, 2026-09-30:
          // no prompts for pings from the Friends feed — only Dip keeps
          // them). ping_post_author still resolves the recipient(s) from
          // the post server-side, so a Duo post pings both authors.
          onTap: _pingAuthor,
        ),
        const SizedBox(height: 22),
        PostReactionCorner(
          // Scaled up with the taller post frame — explicit request: "as
          // the size of post has increased accordingly increase the ping
          // and real emoji button sizes as well".
          size: kPostRailButtonSize,
          allowFaceReactions: true,
          myFaceReaction: null,
          myEmoji: myRealmojiReaction?.glyph,
          mySelfieUrl: _mySelfieUrl,
          uploading: uploadingFaceReaction,
          onTap: openReactionTray,
          onClose: closePresetTray,
          showTray: showPresetTray,
          category: ReactionPresetCategory.everyone,
          onSelect: (preset) => selectPreset(widget.postId, preset),
          onAddNew: () =>
              openAddPresetFlow(widget.postId, allowFaceReactions: true),
          onCaptureRealmoji: (type) => captureRealmojiAndReact(
            widget.postId,
            ReactionPresetCategory.everyone,
            type,
          ),
          // Default ❤️ like, first in the tray.
          onHeart: () => toggleHeart(widget.postId),
          heartLiked: heartLiked,
        ),
      ],
    );
  }
}

/// Two overlapping profile photos for a shared (Duo) post.
///
/// Occupies the same 42px slot a single avatar does, so the header's
/// baseline and the byline width budget (see this card's class doc) are
/// unchanged — the two circles are drawn smaller and offset rather than the
/// row being made wider, which would have pushed the username into an
/// ellipsis on every shared post.
class _FusedAvatar extends StatelessWidget {
  const _FusedAvatar({
    required this.seed,
    this.photoUrl,
    this.partnerPhotoUrl,
    this.pairStreak,
  });

  final String seed;
  final String? photoUrl;
  final String? partnerPhotoUrl;

  /// The pair's ping streak — drawn as a small blue flame badge on the
  /// avatar's own corner instead of a separate element beside the name.
  /// Explicit instruction: "place the blue flame on the users dp" — this is
  /// the Snapchat-style placement (flame pinned to the profile picture
  /// itself), not the earlier "flame + number floating next to the header"
  /// treatment. Null/0 draws nothing.
  final int? pairStreak;

  @override
  Widget build(BuildContext context) {
    // Always the full streak layout, flame included, reading 0 when there is
    // no streak (or it hasn't loaded yet). The avatar used to be 46px with
    // no flame and grow to 55px once a streak arrived, so the header visibly
    // changed a moment after landing — "let it be constant... if there is no
    // streak let it show zero there on the flame".
    final streak = (pairStreak ?? 0) < 0 ? 0 : (pairStreak ?? 0);
    return SizedBox(
      // A few px wider/taller than the face cluster so the corner badge
      // has room to sit on the edge rather than being clipped by it.
      // 20px was tried first and technically worked, but the streak number
      // on a flame that small was reported as "not visible" — not clipped,
      // just too small to actually read. 26px + blueFlameStreak's own
      // legibility floor (see that method's doc) is what fixes that.
      //
      // BUMPED (42/50 -> 46/55, face 26 -> 28, flame 24 -> 26): same
      // "relatively increase the dp" follow-up as the single-face _Avatar
      // default above, applied proportionally to this two-face cluster.
      width: 55,
      height: 55,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 9,
            bottom: 9,
            child: _ring(seed, partnerPhotoUrl),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: _ring('$seed-a', photoUrl),
          ),
          Positioned(
              right: 0,
              bottom: 0,
              child: PV2Icons.blueFlameStreak(
                streak,
                flameSize: 26,
                showZero: true,
              ),
            ),
        ],
      ),
    );
  }

  /// A dark ring around each circle so the two read as separate faces where
  /// they overlap, instead of merging into one blob.
  Widget _ring(String s, String? url) => Container(
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0B0B0E),
        ),
        child: _Avatar(seed: s, photoUrl: url, size: 28),
      );
}

class _Avatar extends StatelessWidget {
  // BUMPED 42 -> 46: explicit follow-up to scale the DP up alongside the
  // post frame, ping/RealMoji buttons (kPostRailButtonSize) and the
  // reaction-viewer chip (ReactionPreviewChip) — "relatively increase the
  // dp as well". The one caller that overrides this (the reactor-list
  // avatar at size: 26) is untouched; only the header DP default changes.
  const _Avatar({required this.seed, this.photoUrl, this.size = 46});
  final String seed;
  final String? photoUrl;
  final double size;

  static const _palette = [
    Color(0xFF8A8F98),
    Color(0xFFB9AD97),
    Color(0xFF9DB29A),
    Color(0xFFA79BBF),
    Color(0xFFD5A8A0),
    Color(0xFF8FA8BD),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[seed.hashCode.abs() % _palette.length];
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          memCacheWidth: (size * 3).round(),
          imageUrl: photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) =>
              Container(width: size, height: size, color: color),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// One Duo name, capped so the "a & b" byline stays on one line without
/// scaling to unreadable sizes.
String _shortName(String name) =>
    name.length <= 16 ? name : '${name.substring(0, 15)}\u2026';
