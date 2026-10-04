import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import 'anon_post_card_clipper.dart';
import 'anon_realmoji_counts.dart';
import 'post_card_shared.dart';
import 'post_card_tray_icons.dart';
import 'reaction_row.dart';

// ---------------------------------------------------------------------------
// PhotoPostCard — the image-dominant post card, used whenever a post has a
// photo. Anonymous posts only.
//
// The image's own frame (four independently-fitted corner radii, the
// avatar notch in its top edge, the reaction-tray cut in its bottom-right)
// is pixel-exact geometry traced off a reference screenshot and re-derived
// for 4:5 portrait (this app's actual capture ratio — 4:5 or 1:1 square
// only, never landscape) — see anon_post_card_clipper.dart (the Post Card
// Implementation Spec's generic framePath(H)/scaleFor(H) generator, ported
// 1:1; deliberately NOT pixel_exact_post_card_clipper.dart, which is
// EveryonePostCard's own separate, decorative-only frame — see that
// clipper's header comment for why the two are kept apart). The frame's
// own aspect ratio (4:5, AnonPostCardGeometry.height) now matches
// [imageAspectRatio]'s default directly, so a 4:5 photo fills it edge-to-
// edge with zero cropping; a 1:1 square photo still renders through the
// same frame via BoxFit.cover (fills exactly one axis, crops the other —
// never stretched, never letterboxed). Per the spec's section 4, the
// reaction + ping icons sit directly in the tray cut, positioned via the
// same traced geometry the cut itself uses (trayTopY/trayIconTopInset/
// trayRightInset/trayIconGap) — see section 2 below.
//
// Top to bottom:
//   1. Header — above the image:
//      Text block only: the ghost prompt question + caption, when present
//      (GhostPromptBlock). The QUESTION fades out as the post comes into
//      full focus (scroll-reveal, via [focusValue]) so nothing but the
//      poster's own written caption is left showing once a post is
//      centered — the prompt itself never appears on a focused post. The
//      caption stays visible regardless of focus. The identity row (avatar)
//      is NOT part of this header anymore — see below.
//   2. The image itself, pixel-exact frame per above. The persona avatar
//      (plain circle, never the real profile photo, never a real name) is
//      a Positioned overlay INSIDE this same Stack, unclipped, at the
//      traced avatarCenter — floating mostly ABOVE the image's own top
//      edge (only 22.2% of its diameter overlaps down into it), with a
//      solid white ring exactly matching the notch the image's own clip
//      was traced against. The reaction (quick-react, Anonymous only) and
//      ping icons are a second Positioned overlay in the same Stack, in the
//      bottom-right tray cut.
//   3. Below the image, one shared glass surface holding others' reactions
//      (scrollable) and "View all N comments" — see _ReactionsAndCommentsRow
//      below. The reactions side is mutually-exclusive on
//      [allowFaceReactions]: ReactionRow (BeReal-style face thumbnails)
//      where allowed, EmojiReactionRow (no photos, per the anonymity rule)
//      on emoji-only feeds like Anonymous — and collapses away entirely
//      (comments alone) when there's nothing to show.
//
// No real name, no real profile photo, no timestamp, no song/audio bar,
// no community tag, no heart, no per-post bell — anywhere on this card,
// ever. Per-post notification subscribe is gone; there's a single
// page-level bell now (see MainShell).
// ---------------------------------------------------------------------------

class PhotoPostCard extends StatefulWidget {
  const PhotoPostCard({
    super.key,
    required this.postId,
    required this.media,
    required this.allowFaceReactions,
    required this.pingContext,
    this.pingTargetName,
    this.onSentPrompt,
    this.personaPhotoUrl,
    this.posterScore,
    this.branch,
    this.promptQuestion,
    this.answerText,
    this.commentCount = 0,
    this.onCommentTap,
    this.cornerRadius = 24,
    this.imageCornerRadius = 22,
    this.imageAspectRatio = 4 / 5,
    this.isLoading = false,
    this.hasError = false,
    this.focusValue,
  });

  /// Reactions are fetched/written keyed on this — must be stable and
  /// unique per post.
  final String postId;

  /// The actual photo/collage content (e.g. wrap SinglePostCard,
  /// MemoryFeedCard, or a raw image). Ignored while [isLoading] or
  /// [hasError] are true. PhotoPostCard is only ever built for posts that
  /// have a photo — route text-only posts to TextPostCard instead.
  final Widget media;

  /// True for Friends/Everyone feeds, false for the Anonymous feed. Face
  /// reactions (the corner entry badge's camera flow, and the BeReal-style
  /// row of others' reactions below the image) only ever engage when this
  /// is true — the Anonymous feed is emoji-only reactions throughout.
  final bool allowFaceReactions;

  /// Passed straight through to showPingPromptSheet — see
  /// ping_prompt_sheet.dart for what this changes (prompt copy, styling).
  final PingContext pingContext;

  /// Name shown inside the ping sheet itself (a separate flow this card
  /// doesn't render) — null falls back to 'someone'. Passing a real name
  /// here does not put a name on the card; the card still shows none.
  final String? pingTargetName;

  /// Forwarded straight to showPingPromptSheet — a caller with somewhere
  /// real to send the prompt (e.g. the Anonymous feed's ping_post_author
  /// RPC) passes this; a caller with nowhere real to send it just omits
  /// it, same posture as DesignGroupCard's own use of this pattern.
  final PingSendHandler? onSentPrompt;

  /// The poster's anon persona photo — never the real profile photo. Null
  /// falls back to a plain silhouette glyph.
  final String? personaPhotoUrl;

  /// Kept on the API for a possible future compact status signal.
  final int? posterScore;

  /// Department/branch (e.g. "CSE") — kept on the API but no longer
  /// rendered anywhere on this card. Individual anonymous posts never show
  /// a community tag (that's now specific to group posts, which are a
  /// different card entirely); this field is inert until/unless a future
  /// caller needs it for something other than the on-image tag this used
  /// to draw.
  final String? branch;

  /// The ghost prompt this post is replying to — shown in the text block
  /// above the image. Null hides the whole text block.
  final String? promptQuestion;

  /// The poster's written caption for [promptQuestion], shown directly
  /// below it in a dimmer, ghosted weight. Ignored if [promptQuestion] is
  /// null.
  final String? answerText;

  final int commentCount;
  final VoidCallback? onCommentTap;

  final double cornerRadius;

  /// Corner radius of the inset image itself (distinct from [cornerRadius],
  /// the outer card) — this is `R` in the notch/dip clip-path geometry
  /// (design-refs/design_handoff_notched_post_card), default matches that
  /// handoff's own default.
  final double imageCornerRadius;

  /// width / height of the photo section. Deliberately NOT sized via
  /// Expanded/"whatever height is left in the page" — that made the image
  /// height a function of ambient PageView/page-chrome space (which can
  /// vary or resolve a frame late via MediaQuery), instead of a stable
  /// function of the card's own width. AspectRatio fixes it in the SAME
  /// layout pass the card's width is known, so there's no "renders small,
  /// then corrects" — the image is exactly this many times taller than
  /// wide from the very first frame. Default 4:5 — a dominant, tall,
  /// portrait-leaning post photo, not a squished thumbnail.
  final double imageAspectRatio;

  /// Card-level (not reaction-level) loading/error — set by the caller when
  /// the post's own content isn't ready/failed. Reaction data has its own
  /// internal loading state independent of this.
  final bool isLoading;
  final bool hasError;

  /// Continuous 0 (peek/off-center) .. 1 (dead-centered, full focus) value
  /// for THIS post, sampled from the feed's scroll position. Drives the
  /// prompt+caption block's opacity below: visible while peeking, faded to
  /// nothing once the post is fully focused, so the centered photo reads
  /// clean. Null (the default) means "no scroll-reveal mechanic wired up" —
  /// the prompt block then just stays fully visible, same as before this
  /// feature existed.
  final ValueListenable<double>? focusValue;

  @override
  State<PhotoPostCard> createState() => _PhotoPostCardState();
}

class _PhotoPostCardState extends State<PhotoPostCard>
    with PostReactions<PhotoPostCard> {
  // Symmetric and minimal — matches the small side gap the Everyone/
  // Friends card now uses (everyone_post_card.dart). Was 28/10 (asymmetric,
  // left-heavy) purely as a side effect of also being the prompt block's
  // own base inset — see _kPromptExtraLeftInset below, which still adds
  // its own extra room ON TOP of this for the prompt specifically, so that
  // relationship (prompt indented further than the avatar/image) survives
  // this shrinking symmetrically rather than needing its own new number.
  static const double _kImageInsetLeft = 10;
  static const double _kImageInsetRight = 10;

  // Used whenever widget.focusValue is null — keeps the prompt block
  // permanently in its "peek" (fully visible) state, matching this card's
  // behavior before the scroll-reveal mechanic existed.
  static final ValueNotifier<double> _kNeverFocused = ValueNotifier(0.0);

  /// RealMoji emoji+count chips (anon_realmoji_counts.dart), sourced from
  /// the anon_reaction_counts view — a separate system from the emoji-only
  /// `reactions` table above, loaded independently so a failure here never
  /// blocks the existing reaction UI. No identity ever touches this list —
  /// see AnonRealmojiCounts' own doc.
  List<AnonRealmojiCount> _realmojiCounts = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading && !widget.hasError) {
      loadReactionSummary(widget.postId);
      unawaited(_loadRealmojiCounts());
      unawaited(loadMyRealmojiReaction(widget.postId));
    }
  }

  @override
  void didUpdateWidget(PhotoPostCard old) {
    super.didUpdateWidget(old);
    final justBecameReady =
        (old.isLoading || old.hasError) &&
        !widget.isLoading &&
        !widget.hasError;
    if (justBecameReady || old.postId != widget.postId) {
      loadReactionSummary(widget.postId);
      unawaited(_loadRealmojiCounts());
      unawaited(loadMyRealmojiReaction(widget.postId));
    }
  }

  Future<void> _loadRealmojiCounts() async {
    try {
      final counts = await RealmojiService.instance.fetchAnonCounts(widget.postId);
      if (!mounted) return;
      setState(() => _realmojiCounts = counts);
    } catch (e, st) {
      debugPrint('[PhotoPostCard] fetchAnonCounts(${widget.postId}) failed: $e\n$st');
    }
  }

  // Extra left inset for the prompt text block, on top of the shared
  // _kImageInsetLeft — deliberately more room than the identity row below
  // it gets, so the prompt reads as a distinct block rather than lining up
  // flush with the avatar underneath it.
  static const double _kPromptExtraLeftInset = 18;

  @override
  Widget build(BuildContext context) {
    final reactions = summary ?? const ReactionSummary.empty();
    final hasPrompt = widget.promptQuestion != null;

    // Others' reactions only — the viewer's own face reaction is shown on
    // the entry badge instead, so it's excluded here to avoid showing it
    // twice.
    final otherFaceReactions = reactions.myFaceReaction == null
        ? reactions.faceReactions
        : reactions.faceReactions
              .where((r) => r.userId != reactions.myFaceReaction!.userId)
              .toList();
    final showFaceReactions =
        widget.allowFaceReactions &&
        (otherFaceReactions.isNotEmpty || (loadingSummary && summary == null));

    // Emoji-only counterpart, for feeds where face reactions aren't
    // allowed (Anonymous). emojiCounts is aggregated per-emoji, not a
    // per-user list, so "others' reactions" here means "my own emoji's
    // count minus one, everyone else's untouched" rather than filtering a
    // list by user id.
    final otherEmojiEntries = <MapEntry<String, int>>[];
    reactions.emojiCounts.forEach((emoji, count) {
      final othersCount = reactions.myEmoji == emoji ? count - 1 : count;
      if (othersCount > 0) otherEmojiEntries.add(MapEntry(emoji, othersCount));
    });
    otherEmojiEntries.sort((a, b) => b.value.compareTo(a.value));
    final showEmojiReactions =
        !widget.allowFaceReactions &&
        (otherEmojiEntries.isNotEmpty || (loadingSummary && summary == null));
    final showReactionsRow = showFaceReactions || showEmojiReactions;

    // This card lives inside AnonymousTab's vertical PageView, which hands
    // each page TIGHT, full-page-height constraints (see TextPostCard's own
    // note on this) — a Column can't refuse that height no matter what
    // mainAxisSize says on its OWN, so without Align the DecoratedBox below
    // would stretch to fill the whole page even once the image stopped
    // being an Expanded/"fill whatever's left" child. Align gives its child
    // loose constraints regardless of what Align itself receives, so the
    // card sizes to its own content (header + fixed-aspect image +
    // comments) and only the leftover page space below it stays empty.
    return Align(
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth;
              final imageWidth =
                  cardWidth - _kImageInsetLeft - _kImageInsetRight;
              // Ideal image height from width alone — used as a
              // Flexible(loose)'s fixed-height child below, NOT a rigid
              // AspectRatio. A plain AspectRatio would shrink the image's
              // WIDTH (not just height) if the page ever has less vertical
              // room than this wants (e.g. on first load, before the
              // SlimHeader's full prompt composer has collapsed on scroll
              // — that alone can leave the whole feed only ~400px tall),
              // which would overflow. Flexible(loose) instead lets the
              // image size down gracefully to whatever's actually
              // available without erroring, while still hitting the full
              // aspect ratio the instant there's room for it.
              //
              // Height comes from AnonPostCardGeometry, NOT
              // widget.imageAspectRatio directly — the traced frame is
              // locked to 4:5 (matching this app's primary capture ratio),
              // so a 4:5 photo fills it exactly, but a 1:1 square photo
              // (imageAspectRatio: 1) still needs BoxFit.cover inside this
              // same frame rather than a shorter frame of its own — see
              // _buildMedia's usage below.
              final geo = AnonPostCardGeometry.of(imageWidth);
              final idealImageHeight = geo.height;
              // The tray-cut apron (from trayTopY to the frame's own
              // bottom edge) is shallower than a real tap-sized icon —
              // same reasoning as the avatar, which floats mostly ABOVE
              // the top edge rather than being squeezed to fit inside the
              // dip. The icons hang below the frame's bottom edge by
              // whatever doesn't fit in the apron; reserved as empty space
              // right after the image (below) so that overflow lands there
              // instead of overlapping _ReactionsAndCommentsRow. Uses the
              // taller of the two (non-square) tray icons, per
              // AnonPostCardGeometry.stickFigureSize/reactionIconSize.
              final maxTrayIconHeight = math.max(
                geo.stickFigureSize.height,
                geo.reactionIconSize.height,
              );
              final trayOverflow =
                  (geo.trayIconTopInset + maxTrayIconHeight - (geo.height - geo.trayTopY))
                      .clamp(0.0, double.infinity);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 0. Top corner controls — own row, above everything else
                  // (including the text block below), independent of
                  // PixelExactCardGeometry's avatar-position math. No
                  // per-post bell (that's page-level now, see MainShell);
                  // this feed (allowFaceReactions: false) never shows
                  // PostTopControlsRow's reaction-library corner either, so
                  // the whole Padding is skipped rather than reserving
                  // blank top space for a row that would render nothing.
                  if (widget.allowFaceReactions)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _kImageInsetLeft,
                        12,
                        16,
                        0,
                      ),
                      child: PostTopControlsRow(
                        allowFaceReactions: widget.allowFaceReactions,
                        myFaceReaction: reactions.myFaceReaction,
                        myEmoji: reactions.myEmoji,
                        uploadingReaction: uploadingFaceReaction,
                        onReactionTap: openReactionTray,
                        onReactionClose: closePresetTray,
                        showReactionTray: showPresetTray,
                        reactionCategory: widget.allowFaceReactions
                            ? ReactionPresetCategory.everyone
                            : ReactionPresetCategory.anonymous,
                        onReactionSelect: (preset) =>
                            selectPreset(widget.postId, preset),
                        onReactionAddNew: () => openAddPresetFlow(
                          widget.postId,
                          allowFaceReactions: widget.allowFaceReactions,
                        ),
                        onReactionCaptureRealmoji: (type) => captureRealmojiAndReact(
                          widget.postId,
                          widget.allowFaceReactions
                              ? ReactionPresetCategory.everyone
                              : ReactionPresetCategory.anonymous,
                          type,
                        ),
                      ),
                    ),

                  // 1. Header — ABOVE the image: text block only (ghost
                  // prompt + caption). The avatar is no longer part of
                  // this section — it's a Positioned overlay inside the
                  // image's own Stack below, at the exact traced
                  // avatarCenter (see PixelExactCardGeometry). A SizedBox
                  // reserves exactly the avatar's own overflow-above-the-
                  // image height right after this block, so the avatar's
                  // unclipped overflow lands in empty reserved space, not
                  // on top of the caption text.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kImageInsetLeft,
                      10,
                      16,
                      0,
                    ),
                    child: hasPrompt
                        // Scroll-reveal: the QUESTION fades out as the
                        // post comes into full focus (focus 1) — a clean
                        // photo with no prompt text over it once
                        // centered. The poster's own CAPTION (answerText)
                        // deliberately does NOT fade with it — per spec,
                        // the only text ever shown on a fully-focused post
                        // is what the user actually typed, so it stays
                        // visible regardless of focus. This is also what
                        // makes the NEXT post's own prompt already peek in
                        // from the bottom of the screen before it's
                        // centered, since its focus starts at 0 the
                        // moment any sliver of it is on screen. A plain
                        // Opacity (no animation) so it tracks the finger
                        // exactly, same reasoning SpotlightCard uses for
                        // its own focus-driven blur/dim.
                        ? ValueListenableBuilder<double>(
                            valueListenable:
                                widget.focusValue ?? _kNeverFocused,
                            builder: (context, focus, _) {
                              final questionOpacity = (1 - focus).clamp(
                                0.0,
                                1.0,
                              );
                              return _promptBlock(questionOpacity);
                            },
                          )
                        : const SizedBox.shrink(),
                  ),
                  SizedBox(
                    height:
                        geo.avatarRingOuterRadius +
                        (-geo.avatarCenter.dy),
                  ),

                  // 2. The image — pixel-exact frame (four corners, avatar
                  // notch, tray cut — see pixel_exact_post_card_clipper.
                  // dart). Sized to the traced 1.6302:1 ratio, NOT
                  // [imageAspectRatio] — see idealImageHeight's comment
                  // above. The actual photo still fills whatever it wants
                  // via BoxFit.cover inside this frame.
                  Flexible(
                    fit: FlexFit.loose,
                    child: SizedBox(
                      height: idealImageHeight,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          _kImageInsetLeft,
                          0,
                          _kImageInsetRight,
                          0,
                        ),
                        // clipBehavior: Clip.none — the avatar below is a
                        // sibling of the clipped image, not inside the
                        // ClipPath's own child, so it paints on top of the
                        // frame, unclipped, per spec ("Renders on top of
                        // the card frame, in front of the clipped photo").
                        //
                        // LayoutBuilder + geo2: idealImageHeight is only
                        // ever a REQUEST to the enclosing Flexible(loose) —
                        // when the page doesn't have enough vertical room,
                        // the actual height this box gets can come back
                        // smaller. AnonPostCardClipper.getClip already
                        // self-adjusts to whatever real `size` it's handed,
                        // but `geo` (computed above, before layout, from
                        // width alone) assumes the IDEAL height — so avatar/
                        // tray positions computed from it can land past the
                        // real, possibly-shrunk frame's own edge. geo2 is
                        // computed from the same real constraints the
                        // clipper itself sees, via
                        // AnonPostCardGeometry.fromSize (see its own doc
                        // comment) — use geo2 for every avatar/tray number
                        // below, geo only for the outer idealImageHeight ask.
                        child: LayoutBuilder(
                          builder: (context, imgConstraints) {
                            final geo2 = AnonPostCardGeometry.fromSize(
                              Size(imgConstraints.maxWidth, imgConstraints.maxHeight),
                            );
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipPath(
                                  clipper: const AnonPostCardClipper(),
                                  child: SizedBox.expand(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: imageWidth,
                                        height: imageWidth / widget.imageAspectRatio,
                                        child: _buildMedia(),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left:
                                      geo2.avatarCenter.dx -
                                      geo2.avatarRingOuterRadius,
                                  top:
                                      geo2.avatarCenter.dy -
                                      geo2.avatarRingOuterRadius,
                                  child: Container(
                                    width: geo2.avatarRingOuterRadius * 2,
                                    height: geo2.avatarRingOuterRadius * 2,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    alignment: Alignment.center,
                                    child: PersonaPhoto(
                                      photoUrl: widget.personaPhotoUrl,
                                      score: widget.posterScore ?? 0,
                                      size: geo2.avatarRadius * 2,
                                      ringWidth: 0,
                                    ),
                                  ),
                                ),
                                // Reaction + ping — bottom-right tray cut,
                                // per POST_CARD_SPEC.md section 4.
                                // Positioned via the same traced geometry
                                // the cut itself uses (trayTopY/
                                // trayIconTopInset/trayRightInset/
                                // trayIconGap) so the icons land exactly
                                // inside the white notch the clip path
                                // already carves.
                                Positioned(
                                  right: geo2.trayRightInset,
                                  top: geo2.trayTopY + geo2.trayIconTopInset,
                                  // Spec section 4: left → right = stick
                                  // figure (ping), then reaction (smiley+
                                  // plus) — the reaction icon sits closest
                                  // to the tray's own right inset.
                                  child: Row(
                                    children: [
                                      PostPingButton(
                                        onTap: () => openPing(
                                          pingContext: widget.pingContext,
                                          targetName: widget.pingTargetName,
                                          onSentPrompt: widget.onSentPrompt,
                                        ),
                                        width: geo2.stickFigureSize.width,
                                        height: geo2.stickFigureSize.height,
                                        style: TrayIconVisualStyle.glyph,
                                      ),
                                      if (!widget.allowFaceReactions) ...[
                                        SizedBox(width: geo2.trayIconGap),
                                        // This icon stays exactly where it
                                        // already was (per explicit
                                        // correction: no new icon anywhere
                                        // on the post) — only its tray
                                        // content is repointed, from the
                                        // old ReactionPresetService-backed
                                        // ReactionPresetTray to RealmojiTray
                                        // (user_realmojis-backed). See
                                        // PostReactions.selectPreset /
                                        // captureRealmojiAndReact.
                                        PostReactionCorner(
                                          allowFaceReactions: false,
                                          myFaceReaction: null,
                                          myEmoji: myRealmojiReaction?.glyph,
                                          uploading: uploadingFaceReaction,
                                          onTap: openReactionTray,
                                          onClose: closePresetTray,
                                          showTray: showPresetTray,
                                          category:
                                              ReactionPresetCategory.anonymous,
                                          onSelect: (preset) =>
                                              selectPreset(widget.postId, preset),
                                          onAddNew: () => openAddPresetFlow(
                                            widget.postId,
                                            allowFaceReactions: false,
                                          ),
                                          onCaptureRealmoji: (type) => captureRealmojiAndReact(
                                            widget.postId,
                                            ReactionPresetCategory.anonymous,
                                            type,
                                          ),
                                          width: geo2.reactionIconSize.width,
                                          height: geo2.reactionIconSize.height,
                                          style: TrayIconVisualStyle.glyph,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: trayOverflow),

                  // RealMoji emoji+count chips (realmoji_service.dart /
                  // anon_realmoji_counts.dart) — entry point ('+') lives in
                  // the tray row above now, not here; this is purely the
                  // "what's been reacted" display. Emoji+count ONLY — no
                  // faces, no names, ever, per this feed's anonymity rule.
                  // Never renders an empty slot.
                  if (_realmojiCounts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: AnonRealmojiCounts(counts: _realmojiCounts),
                    ),

                  // 3. Below the image: ONE shared glass surface holding
                  // the quick-react entry, others'-reactions, ping, and
                  // comments — see _ReactionsAndCommentsRow. Which
                  // reactions side renders is mutually exclusive on
                  // [allowFaceReactions]: face thumbnails where allowed,
                  // emoji-count chips (no photos) on emoji-only feeds like
                  // Anonymous; collapses to comments-alone when there's
                  // nothing to show.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: RepaintBoundary(
                      child: _ReactionsAndCommentsRow(
                        showReactionsRow: showReactionsRow,
                        showFaceReactions: showFaceReactions,
                        otherFaceReactions: otherFaceReactions,
                        otherEmojiEntries: otherEmojiEntries,
                        reactionsLoading: loadingSummary && summary == null,
                        commentCount: widget.commentCount,
                        onCommentTap: widget.onCommentTap,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The ghost prompt + caption block, extracted so the scroll-driven
  /// Opacity above can wrap it without duplicating the content definition.
  /// [questionOpacity] fades ONLY the prompt question — the caption
  /// (answerText) always stays fully visible, per spec: the only text ever
  /// shown on a fully-focused post is what the user actually typed.
  Widget _promptBlock(double questionOpacity) {
    return Padding(
      padding: const EdgeInsets.only(left: _kPromptExtraLeftInset),
      child: LayoutBuilder(
        builder: (context, c) => GhostPromptBlock(
          question: widget.promptQuestion!,
          answer: widget.answerText,
          maxWidth: c.maxWidth,
          questionOpacity: questionOpacity,
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.hasError) {
      return Container(
        color: const Color(0xFFF0F0F0),
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Color(0xFF999999),
            size: 40,
          ),
        ),
      );
    }
    if (widget.isLoading) {
      return Shimmer.fromColors(
        baseColor: const Color(0xFFECECEC),
        highlightColor: const Color(0xFFF8F8F8),
        child: Container(color: Colors.white),
      );
    }
    return widget.media;
  }
}

// ---------------------------------------------------------------------------
// _ReactionsAndCommentsRow — others'-reactions and "View all N comments" in
// ONE shared glass surface, side by side rather than stacked, so a viewer
// can see who reacted and jump to comments in the same glance. The
// reactions side is horizontally scrollable and takes whatever width is
// left after the (fixed-width) comment text; when there's nothing to show
// there, the comment content alone occupies the row (unchanged from the
// old stacked layout's comment-only case).
// ---------------------------------------------------------------------------

class _ReactionsAndCommentsRow extends StatelessWidget {
  const _ReactionsAndCommentsRow({
    required this.showReactionsRow,
    required this.showFaceReactions,
    required this.otherFaceReactions,
    required this.otherEmojiEntries,
    required this.reactionsLoading,
    required this.commentCount,
    required this.onCommentTap,
  });

  final bool showReactionsRow;
  final bool showFaceReactions;
  final List<FaceReaction> otherFaceReactions;
  final List<MapEntry<String, int>> otherEmojiEntries;
  final bool reactionsLoading;

  final int commentCount;
  final VoidCallback? onCommentTap;

  static const double _kThumbSize = 28;

  @override
  Widget build(BuildContext context) {
    return LightSurfaceBox(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            if (showReactionsRow) ...[
              Expanded(
                child: SizedBox(
                  height: _kThumbSize,
                  child: showFaceReactions
                      ? ReactionRow(
                          reactions: otherFaceReactions,
                          isLoading: reactionsLoading,
                          thumbSize: _kThumbSize,
                          embedded: true,
                        )
                      : EmojiReactionRow(
                          entries: otherEmojiEntries,
                          isLoading: reactionsLoading,
                          thumbSize: _kThumbSize,
                          embedded: true,
                        ),
                ),
              ),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ],
            GestureDetector(
              onTap: onCommentTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mode_comment_outlined,
                    size: 15,
                    color: kClusterGray,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    commentCount > 0
                        ? 'View all $commentCount comments'
                        : 'Add a comment…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: kClusterGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
