import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:math' as math;
import 'dart:ui';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../core/supabase_config.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../features/moderation/post_actions_menu.dart'
    show showCommentActionsMenu;
import '../../../features/profile_v2/profile_navigation.dart';
import '../../../services/anon_persona_service.dart';
import '../../../services/comment_service.dart';
import '../../../services/content_moderation_service.dart';
import '../../../services/current_user_service.dart';
import '../../../services/post_service.dart' show PostViewer;
import '../../../services/presence_service.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../features/home/anon_feed_v2/anon_feed_icons.dart'
    show ChevronRightPainter;
import '../../../features/home/anon_feed_v2/anon_feed_tokens.dart'
    show AnonFeedColors, AnonFeedType;
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import '../../../shared/time_ago.dart';
import '../../reactions/reaction_library_screen.dart' show runAddPresetFlow;
import '../../reactions/realmoji_library_screen.dart';
import 'face_reaction_capture.dart';
import 'post_card_tray_icons.dart';
import 'realmoji_tray.dart';

// ---------------------------------------------------------------------------
// Shared building blocks for PhotoPostCard and TextPostCard
// (photo_post_card.dart / text_post_card.dart), per POST_CARD_SPEC.md. This
// file holds what's genuinely identical between the two card widgets: the
// reaction/ping state machine (PostReactions), the top-left quick-react
// entry badge (ReactionEntryBadge), and the small presentational pieces
// (PersonaPhoto, BranchTag, GhostPromptBlock, TopActionIcons, CommentRow,
// WordSafeText). Face-reaction thumbnails (BeReal-style) are NOT part of
// TopActionIcons anymore — per spec they're their own row below the image,
// using ReactionRow directly (see photo_post_card.dart).
// ---------------------------------------------------------------------------

/// Reaction + ping state, shared by both card widgets so the ~150 lines of
/// ReactionService/Supabase plumbing isn't duplicated across two State
/// classes. Mixed onto `State<T>`, so it already has `context`/`setState`/
/// `mounted` — callers only need to supply the postId (and ping details)
/// per call, since those live on the concrete widget, not the mixin.
/// Fires with the id of a post whose reactions just changed, so any card
/// currently rendering that post's counts can refresh itself.
///
/// Exists because the write and the display live in different widgets:
/// SpotlightCard owns the double-tap / long-press gestures, while the
/// count is rendered by whichever card is its `child` (DesignSoloCard,
/// DesignGroupCard). The only channel between them was
/// SpotlightPrivilegesController.reactionEvents, which drives the floating
/// emoji animation and nothing else — so a reaction was written, animated,
/// and the visible count stayed stale until a manual refresh.
///
/// Carries the id rather than a bare tick so a feed full of cards does one
/// refetch on the card that changed, not N refetches on every card.
final reactionsChangedForPost = ValueNotifier<String?>(null);

/// Announces a reaction write. Safe to call for either namespace — pass
/// whichever id identifies the post (`posts.id` or `group_posts.id`); the
/// mixin matches on the same value it was loaded with.
void notifyReactionsChanged(String postId) {
  // Reassign even when the id repeats: ValueNotifier suppresses identical
  // values, and reacting twice to the same post must still refresh.
  reactionsChangedForPost.value = null;
  reactionsChangedForPost.value = postId;
}

mixin PostReactions<T extends StatefulWidget> on State<T> {
  ReactionSummary? summary;
  bool loadingSummary = false;

  /// What [loadReactionSummary] was last called with, so the listener
  /// below can tell whether an incoming change concerns this card.
  String? _summaryPostId;
  String? _summaryGroupPostId;

  @override
  void initState() {
    super.initState();
    reactionsChangedForPost.addListener(_onReactionsChanged);
  }

  @override
  void dispose() {
    reactionsChangedForPost.removeListener(_onReactionsChanged);
    super.dispose();
  }

  void _onReactionsChanged() {
    final changed = reactionsChangedForPost.value;
    if (changed == null || !mounted) return;
    if (changed != _summaryPostId && changed != _summaryGroupPostId) return;
    unawaited(
      loadReactionSummary(_summaryPostId, groupPostId: _summaryGroupPostId),
    );
  }

  bool showEmojiPicker = false;
  bool uploadingFaceReaction = false;

  /// Drives RealmojiTray's visibility — shown instead of a fresh camera
  /// capture when the entry badge is tapped (see openReactionTray below).
  /// Independent of showEmojiPicker, which still belongs solely to the
  /// bottom-right heart's fixed 🔥/💀 quick-react popup.
  bool showPresetTray = false;

  /// The caller's own RealMoji reaction on this post, if any — drives
  /// PostReactionButton's "already reacted" glow (its myEmoji param) now
  /// that the tray writes to post_realmoji_reactions instead of the old
  /// `reactions` table. See RealmojiService.myReaction's own doc for why
  /// this is safe to read even on an anon post.
  RealmojiType? myRealmojiReaction;

  Future<void> loadMyRealmojiReaction(
    String? postId, {
    String? groupPostId,
  }) async {
    try {
      final reaction = await RealmojiService.instance.myReaction(
        postId,
        groupPostId: groupPostId,
      );
      if (!mounted) return;
      setState(() => myRealmojiReaction = reaction);
    } catch (e, st) {
      debugPrint(
        '[PostReactions.loadMyRealmojiReaction] postId=$postId failed: $e\n$st',
      );
      // Non-fatal — the badge just shows unreacted, same fail-closed
      // convention loadReactionSummary uses below.
    }
  }

  Future<void> loadReactionSummary(
    String? postId, {
    String? groupPostId,
  }) async {
    // Remembered so _onReactionsChanged can match a later write against
    // this card without the mixin needing to know the widget's shape.
    _summaryPostId = postId;
    _summaryGroupPostId = groupPostId;
    if (!mounted) return;
    setState(() => loadingSummary = true);
    try {
      final result = await ReactionService.instance.fetchSummary(
        postId,
        groupPostId: groupPostId,
      );
      if (!mounted) return;
      setState(() {
        summary = result;
        loadingSummary = false;
      });
    } catch (e, st) {
      debugPrint(
        '[PostReactions.loadReactionSummary] fetchSummary($postId) failed: $e\n$st',
      );
      if (!mounted) return;
      setState(() => loadingSummary = false);
      // Reaction load failure isn't fatal to the card — it just shows the
      // bare add-reaction icon with no count, same as the empty state.
    }
  }

  /// Plain-emoji reaction (the `reactions` table), toggling off if it's
  /// already yours. Also backs the tray's default ❤️ (see
  /// [toggleHeart]). [groupPostId] targets a group post instead.
  Future<void> onEmojiSelected(
    String? postId,
    String emoji, {
    String? groupPostId,
  }) async {
    setState(() => showEmojiPicker = false);
    final previous = summary ?? const ReactionSummary.empty();
    final removing = previous.myEmoji == emoji;

    final counts = Map<String, int>.from(previous.emojiCounts);
    if (previous.myEmoji != null) {
      final prevCount = (counts[previous.myEmoji!] ?? 1) - 1;
      if (prevCount <= 0) {
        counts.remove(previous.myEmoji);
      } else {
        counts[previous.myEmoji!] = prevCount;
      }
    }
    if (!removing) counts[emoji] = (counts[emoji] ?? 0) + 1;

    setState(() {
      summary = ReactionSummary(
        emojiCounts: counts,
        myEmoji: removing ? null : emoji,
        faceReactions: previous.faceReactions,
        myFaceReaction: previous.myFaceReaction,
      );
    });

    HapticFeedback.selectionClick();
    try {
      if (removing) {
        await ReactionService.instance.removeEmojiReaction(
          postId,
          groupPostId: groupPostId,
        );
      } else {
        await ReactionService.instance.setEmojiReaction(
          postId: postId,
          groupPostId: groupPostId,
          emoji: emoji,
        );
        // Real Anon Score credit for this now happens server-side, on the
        // POST AUTHOR (not the reactor) — see
        // trg_award_anon_engagement_reactions, only when the reacted-to
        // post is anonymous. No client-side bump belongs here any more.
      }
    } catch (e, st) {
      debugPrint(
        '[PostReactions.onEmojiSelected] postId=$postId emoji=$emoji failed: $e\n$st',
      );
      if (!mounted) return;
      setState(() => summary = previous);
      showGlassToast(context, "Couldn't save your reaction.", isError: true);
    }
  }

  /// Whether the viewer has liked this post with the default heart.
  bool get heartLiked => summary?.myEmoji == kHeartEmoji;

  /// The reaction tray's default ❤️ ("give a default heart button to like
  /// the post"): no selfie needed. Saved as a plain-emoji reaction, so it
  /// counts in the post's reaction summary and in the poster's profile
  /// (fetchSummary / fetchRecentReactors read both reaction tables).
  /// Tapping it again unlikes.
  Future<void> toggleHeart(String? postId, {String? groupPostId}) async {
    closePresetTray();
    await onEmojiSelected(postId, kHeartEmoji, groupPostId: groupPostId);
    final changedId = postId ?? groupPostId;
    if (changedId != null) notifyReactionsChanged(changedId);
  }

  void toggleEmojiPicker() {
    HapticFeedback.selectionClick();
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  /// Opens the quick-pick tray of the viewer's own saved reaction presets
  /// (reaction_preset_tray.dart) — this is what the entry badge now opens
  /// on tap, REPLACING the old "jump straight into a fresh camera capture
  /// every time" behavior. The tray itself resolves category (Anonymous
  /// emoji-only vs. Everyone face+emoji) from whatever
  /// ReactionPresetCategory the calling card passes it — this method just
  /// toggles visibility.
  void openReactionTray() {
    HapticFeedback.selectionClick();
    setState(() => showPresetTray = true);
  }

  void closePresetTray() => setState(() => showPresetTray = false);

  /// Applies a saved RealMoji preset (from RealmojiTray) to this post — an
  /// instant write to post_realmoji_reactions, no camera, no re-upload
  /// (the selfie already lives in storage under user_realmojis). REPOINTED
  /// from the old ReactionService.setFaceReactionFromPreset/setEmojiReaction
  /// (the `reactions` table) — preset.emoji is a RealMoji glyph now, mapped
  /// back to its RealmojiType via realmojiTypeFromGlyph. Still named
  /// selectPreset (not renamed) so both card files' existing
  /// `onSelect: (preset) => selectPreset(widget.postId, preset)` wiring
  /// needs no change. Reuses uploadingFaceReaction as the badge's in-flight
  /// indicator, same as before — it's still a real network write.
  Future<void> selectPreset(
    String? postId,
    ReactionPreset preset, {
    String? groupPostId,
  }) async {
    setState(() => showPresetTray = false);
    HapticFeedback.selectionClick();

    final type = realmojiTypeFromGlyph(preset.emoji);
    setState(() => uploadingFaceReaction = true);
    try {
      await RealmojiService.instance.reactWithSaved(
        postId: postId,
        groupPostId: groupPostId,
        emojiType: type,
      );
      if (mounted) setState(() => myRealmojiReaction = type);
      // A RealMoji is part of this post's reaction summary, so the visible
      // count has to refetch too — setting myRealmojiReaction only updates
      // this card's own "you reacted" glow.
      final changedId = postId ?? groupPostId;
      if (changedId != null) notifyReactionsChanged(changedId);
    } catch (e, st) {
      debugPrint(
        '[PostReactions.selectPreset] postId=$postId preset=${preset.id} failed: $e\n$st',
      );
      if (!mounted) return;
      showGlassToast(context, "Couldn't apply that reaction.", isError: true);
    } finally {
      if (mounted) setState(() => uploadingFaceReaction = false);
    }
  }

  /// RealmojiTray's fallback for a slot with no saved selfie yet (its
  /// onCaptureNeeded) — opens the circular capture sheet, then uploads +
  /// saves + reacts in one call. REPLACES the old openAddPresetFlow (still
  /// defined below, now unreachable from the tray — see its own doc).
  Future<void> captureRealmojiAndReact(
    String? postId,
    ReactionPresetCategory category,
    RealmojiType type, {
    String? groupPostId,
  }) async {
    setState(() => showPresetTray = false);
    // Full-screen push, not a sheet — the reaction camera is a full-screen
    // capture flow per its own design spec (design-refs/
    // design_handoff_group_post_cards 2/README-camera.md).
    final result = await Navigator.of(context).push<FaceReactionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaceReactionCapture(
          presetEmoji: type.glyph,
          title: 'Capture your RealMoji',
          accentColor: AppColors.neonCyan,
          onFallbackToEmoji: () {
            if (context.mounted) {
              showGlassToast(
                context,
                'Front camera needed for a RealMoji — try again once it\'s available.',
                isError: true,
              );
            }
          },
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => uploadingFaceReaction = true);
    try {
      await RealmojiService.instance.captureAndReact(
        postId: postId,
        groupPostId: groupPostId,
        feedScope: category.wire,
        emojiType: type,
        selfie: result.selfie,
      );
      if (mounted) setState(() => myRealmojiReaction = type);
      // A RealMoji is part of this post's reaction summary, so the visible
      // count has to refetch too — setting myRealmojiReaction only updates
      // this card's own "you reacted" glow.
      final changedId = postId ?? groupPostId;
      if (changedId != null) notifyReactionsChanged(changedId);
    } catch (e, st) {
      debugPrint(
        '[PostReactions.captureRealmojiAndReact] postId=$postId type=$type failed: $e\n$st',
      );
      if (!mounted) return;
      showGlassToast(context, "Couldn't save your RealMoji.", isError: true);
    } finally {
      if (mounted) setState(() => uploadingFaceReaction = false);
    }
  }

  /// The OLD tray's "+ add new" — jumps into the legacy preset add flow
  /// (reaction_library_screen.dart's runAddPresetFlow). No longer called by
  /// anything: RealmojiTray has no add-new bolt (its 6 slots are fixed, see
  /// realmoji_tray.dart), so PostReactionCorner.onAddNew is now unreached
  /// from either card. Left defined, not deleted — both card files still
  /// pass `onAddNew: () => openAddPresetFlow(...)` and PostReactionCorner
  /// still requires the param; removing it means touching 3 more files for
  /// a currently-harmless no-op.
  /// [postId] is null for a group post — pass [groupPostId] instead, the
  /// same either/or the rest of this mixin already uses (selectPreset,
  /// captureRealmojiAndReact, loadReactionSummary).
  Future<void> openAddPresetFlow(
    String? postId, {
    required bool allowFaceReactions,
    String? groupPostId,
  }) async {
    setState(() => showPresetTray = false);
    final category = allowFaceReactions
        ? ReactionPresetCategory.everyone
        : ReactionPresetCategory.anonymous;
    final preset = await runAddPresetFlow(context, category);
    if (preset == null || !mounted) return;
    await selectPreset(postId, preset, groupPostId: groupPostId);
  }

  /// Defaults now match the frosted-glass, ~half-screen sheet used
  /// everywhere ping opens from (PhotoPostCard's notch, TextPostCard's
  /// action row) — callers no longer need to repeat those three params just
  /// to get the standard look. Wrapped in try/catch with a debugPrint: this
  /// was previously a silent no-op on failure (e.g. if `context` were ever
  /// unmounted mid-tap), which is exactly the kind of bug that looks like
  /// "the button does nothing" with zero signal in the console.
  void openPing({
    required PingContext pingContext,
    String? targetName,
    bool glass = true,
    double sheetHeightFraction = 0.5,
    bool roundedTopOnly = true,
    // Forwarded straight to showPingPromptSheet — a caller with somewhere
    // real to send the prompt (e.g. DesignGroupCard fanning it out to every
    // group member via PingService) passes this; callers with nowhere real
    // to send it (e.g. personal posts, which have no persistence backend
    // for Ping) just omit it, same as before this param existed.
    PingSendHandler? onSentPrompt,
    // The post being pinged — selects which tier of ping prompts the sheet
    // offers (see PingPromptService.fetchForPost). Null falls back to the
    // generic set, which is what a promptless context should get.
    String? postId,

    /// False suppresses the score-reward panel after a successful send.
    /// The FEED cards pass false — explicit request: "when I ping a person
    /// in friends feed no need to show the drop down of awarding points,
    /// but still the points shall get awarded". Every other ping surface
    /// (profile, group profile, ping page) keeps it.
    bool showScoreReward = false,
  }) {
    HapticFeedback.lightImpact();
    try {
      showPingPromptSheet(
        context,
        targetName: targetName ?? 'someone',
        pingContext: pingContext,
        glass: glass,
        heightFraction: sheetHeightFraction,
        roundedTopOnly: roundedTopOnly,
        onSentPrompt: onSentPrompt,
        postId: postId,
        showScoreReward: showScoreReward,
      );
    } catch (e, st) {
      debugPrint('[PostReactions.openPing] failed to open ping sheet: $e\n$st');
    }
  }
}

/// Pushes RealmojiLibraryScreen — REPOINTED from the old
/// ReactionLibraryScreen (reaction_library_screen.dart), which this
/// function used to open; that screen and its ReactionPresetService backing
/// are now unreferenced by this call site (still reachable directly if
/// something else imports them — see reaction_library_screen.dart's own
/// doc). [allowFaceReactions] is the historical param name (true = Everyone
/// scope, false = Anonymous) — kept as-is since both call sites
/// (home_screen.dart's header, main_shell.dart's copy) already pass it;
/// home_screen.dart now derives it from the actually-active feed tab
/// instead of hardcoding false, see its own call site.
void openReactionLibrary(
  BuildContext context, {
  required bool allowFaceReactions,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RealmojiLibraryScreen(
        feedScope: allowFaceReactions
            ? ReactionPresetCategory.everyone
            : ReactionPresetCategory.anonymous,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// The per-post "bell" (PostSubscription mixin + PostBellButton) used to
// live here — removed along with the icon (see PostTopControlsRow above).
// Its backing service, post_subscription_service.dart, is now unreferenced
// by anything in the app; left in place rather than deleted in case a
// future page-level bell (MainShell) wants the same subscribe/toggle
// backend — flagged here rather than silently orphaned.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Post top controls — per POST_CARD_SPEC.md, "no per-post bell — anywhere
// on this card, ever... a single page-level bell now" (MainShell). The
// per-post bell (PostBellButton, PostSubscription-backed subscribe/mute
// toggle) was still rendering here despite that; removed, along with the
// mixin wiring in PhotoPostCard/TextPostCard that fed it. What's left is
// just ReactionLibraryButton-family controls — see PostTopControlsRow
// below, which collapses to nothing on feeds with no reaction corner to
// show (Anonymous) rather than leaving a blank reserved row where the bell
// used to sit.
// ---------------------------------------------------------------------------

/// The old top-right control (opened the whole saved-preset LIBRARY —
/// browse/add/delete). Superseded by [PostReactionButton] below, which is
/// what the top-right corner now shows on every card — this manager screen
/// (reaction_library_screen.dart) is still fully functional and reachable
/// via ReactionPresetTray's own "+ add new" option, but as of this pass it
/// has no other direct entry point in the app. Kept here, unused by the
/// cards, in case a future screen (e.g. Profile settings) wants to wire it
/// back in — not dead code to delete, just currently unreferenced by
/// PostTopControlsRow.
class ReactionLibraryButton extends StatelessWidget {
  const ReactionLibraryButton({super.key, required this.onTap, this.size = 26});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _RealmojiMarkPainter()),
      ),
    );
  }
}

/// The RealMoji mark.
///
/// This entry point used to be a flat grey circle with a generic `+` in it
/// — indistinguishable from every other add button in the app, and saying
/// nothing about what's behind it. A RealMoji is *your own face, shot for
/// one specific reaction*, so the mark is exactly that: a camera aperture
/// ring around a face, with a shutter notch at the top and a small plus
/// bead where an "add" affordance belongs.
///
/// Painted rather than assembled from Icons so it reads cleanly at the 26
/// and 36px both call sites use, and so the ring gradient can run through
/// the app's own accents (cyan -> magenta -> gold) instead of a flat tint.
/// It carries its own dark disc, so it holds on the Anon tab's dark header
/// and the Friends tab's light one alike.
class _RealmojiMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2;

    // Aperture ring — one unbroken circle. It was drawn as an arc with a
    // gap at the top and an "add" bead sitting in that gap, which at 36px
    // read as a nicked, star-ish shape rather than a mark; explicit
    // correction: "let it be a complete circle".
    final ringWidth = s * 0.09;
    final ringRect = Rect.fromCircle(center: c, radius: r - ringWidth / 2);
    canvas.drawCircle(
      c,
      r - ringWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            AppColors.neonCyan,
            AppColors.vibrantMagenta,
            AppColors.gold,
            AppColors.neonCyan,
          ],
        ).createShader(ringRect),
    );

    // Body — dark disc so the face reads on any header background.
    canvas.drawCircle(
      c,
      r - ringWidth * 1.35,
      Paint()..color = const Color(0xFF141418),
    );

    // The face: two eyes and a smile, sized off the disc rather than
    // hardcoded, so the mark stays balanced at any size.
    final eyeR = s * 0.055;
    final eyeDy = c.dy - s * 0.075;
    final eyeDx = s * 0.135;
    final ink = Paint()..color = const Color(0xFFF2F2F4);
    canvas.drawCircle(Offset(c.dx - eyeDx, eyeDy), eyeR, ink);
    canvas.drawCircle(Offset(c.dx + eyeDx, eyeDy), eyeR, ink);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + s * 0.03),
        width: s * 0.34,
        height: s * 0.26,
      ),
      0.25,
      math.pi - 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.075
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF2F2F4),
    );
  }

  @override
  bool shouldRepaint(covariant _RealmojiMarkPainter oldDelegate) => false;
}

/// The BeReal-style reaction entry point, styled to match PostBellButton's
/// light-outline language (this sits on the card's own white surface, above
/// the image, unlike ReactionEntryBadge which floats on the photo itself and
/// needs a heavier dark fill to hold up there). Tapping it is wired by the
/// caller to PostReactions.openReactionTray — the actual preset picker is
/// [PostReactionCorner] below, which owns showing it as a floating popup.
class PostReactionButton extends StatelessWidget {
  const PostReactionButton({
    super.key,
    required this.allowFaceReactions,
    required this.myFaceReaction,
    required this.myEmoji,
    required this.uploading,
    required this.onTap,
    this.size = 26,
    this.width,
    this.height,
    this.style = TrayIconVisualStyle.surface,
    this.mySelfieUrl,
  });

  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;
  final VoidCallback onTap;
  final double size;

  /// The caller's own saved RealMoji selfie photo for [myEmoji]'s type
  /// (RealmojiService.savedSelfieUrl) — when present, the reacted circle
  /// fills with this real photo instead of the coral-tint placeholder,
  /// matching the design's "reacted state fills the whole circle" intent
  /// with real content instead of its static demo pickedColor.
  final String? mySelfieUrl;

  /// Overrides [size] for a non-square box (the tray's glyph style is
  /// 22×19, not square) — null on both falls back to [size] on both axes,
  /// unchanged from before this param existed.
  final double? width;
  final double? height;

  /// [TrayIconVisualStyle.glyph] renders the spec's solid-black-circle
  /// smiley+plus glyph (post_card_tray_icons.dart) with no extra
  /// container — used only by PhotoPostCard's tray (Anonymous feed).
  /// Every other call site (EveryonePostCard's top-right corner,
  /// TextPostCard) stays on the default [TrayIconVisualStyle.surface] look
  /// below, untouched.
  final TrayIconVisualStyle style;

  // OR, not the old allowFaceReactions-gated either/or: both callers now
  // always pass myFaceReaction: null (RealMoji reactions flow through
  // myEmoji regardless of category — see PostReactions.myRealmojiReaction),
  // so gating on allowFaceReactions would make this permanently false for
  // allowFaceReactions:true callers (EveryonePostCard). Equivalent to the
  // old behavior for any caller that still only ever sets one of the two.
  bool get _reacted => myFaceReaction != null || myEmoji != null;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;

    if (style == TrayIconVisualStyle.glyph) {
      return TrayHitTarget(
        width: w,
        height: h,
        onTap: onTap,
        child: _glyphContent(w, h),
      );
    }

    // §A3: RealMoji button is a WHITE circle (background:#fff) with a dark
    // outline smiley when idle — was a black circle + white icon, the
    // inverse of spec. Reacted state keeps its own coral tint (this app has
    // no per-user "picked selfie color" to fill with yet, unlike the design
    // file's static pickedColor demo data).
    final showSelfie = _reacted && mySelfieUrl != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: w,
        height: h,
        clipBehavior: showSelfie ? Clip.antiAlias : Clip.none,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: showSelfie
              ? null
              : _reacted
              ? AppColors.coral.withValues(alpha: 0.12)
              : Colors.white,
          border: _reacted && !showSelfie
              ? Border.all(
                  color: AppColors.coral.withValues(alpha: 0.45),
                  width: 1.5,
                )
              : null,
          boxShadow: _reacted
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: showSelfie
            ? CachedNetworkImage(
                memCacheWidth: 1080,
                imageUrl: mySelfieUrl!,
                fit: BoxFit.cover,
                width: w,
                height: h,
              )
            : Center(child: _content()),
      ),
    );
  }

  /// The tray glyph is the whole button — no separate circle chip drawn
  /// around it (the spec's black circle is baked into the glyph artwork
  /// itself). Uploading/reacted states reuse the same black-circle base so
  /// they don't visually clash with the idle glyph mid-transition.
  Widget _glyphContent(double w, double h) {
    if (uploading) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
        ),
        child: Center(
          child: SizedBox(
            width: h * 0.4,
            height: h * 0.4,
            child: const CircularProgressIndicator(
              strokeWidth: 1.75,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    if (!allowFaceReactions && myEmoji != null) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
        ),
        child: Center(
          child: Text(myEmoji!, style: TextStyle(fontSize: h * 0.5)),
        ),
      );
    }
    return CustomPaint(size: Size(w, h), painter: const ReactionGlyphPainter());
  }

  Widget _content() {
    final iconSize = size * 0.56;
    if (uploading) {
      return SizedBox(
        width: iconSize * 0.7,
        height: iconSize * 0.7,
        child: const CircularProgressIndicator(
          strokeWidth: 1.75,
          color: Color(0xFF999999),
        ),
      );
    }
    if (allowFaceReactions && myFaceReaction != null) {
      return ClipOval(
        child: SizedBox(
          width: size - 4,
          height: size - 4,
          child: CachedNetworkImage(
            memCacheWidth: 1080,
            imageUrl: myFaceReaction!.photoUrl,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Icon(
              Icons.face_retouching_natural,
              size: iconSize,
              color: AppColors.coral,
            ),
          ),
        ),
      );
    }
    if (!allowFaceReactions && myEmoji != null) {
      return Text(myEmoji!, style: TextStyle(fontSize: iconSize * 0.85));
    }
    // §A3: dark outline smiley (stroke #1a1a1a) on the white circle — exact
    // glyph ported from the design source's own SVG (RealMojiSmileyPainter).
    return CustomPaint(
      size: Size(iconSize, iconSize),
      painter: const RealMojiSmileyPainter(),
    );
  }
}

/// Wraps [PostReactionButton] and owns showing [ReactionPresetTray] as a
/// floating popup that RISES ABOVE the button rather than dropping below
/// it — per spec, the tray must not overlap the button it opens from.
///
/// This can't be a plain Positioned+Stack: every card is wrapped in an
/// outer ClipRRect (the card's own rounded corners), and this button sits
/// in the very first row at the top of that card — there's no room "above"
/// it within the card's own bounds for a Positioned child to occupy without
/// being clipped. Instead this inserts a real OverlayEntry into the
/// nearest Overlay (the same mechanism dialogs/tooltips use), anchored to
/// this button's own on-screen position via its RenderBox — so the tray
/// paints above and outside the card entirely, never clipped by it.
class PostReactionCorner extends StatefulWidget {
  const PostReactionCorner({
    super.key,
    required this.allowFaceReactions,
    required this.myFaceReaction,
    required this.myEmoji,
    required this.uploading,
    required this.onTap,
    required this.onClose,
    required this.showTray,
    required this.category,
    required this.onSelect,
    required this.onAddNew,
    required this.onCaptureRealmoji,
    this.size = 26,
    this.width,
    this.height,
    this.style = TrayIconVisualStyle.surface,
    this.mySelfieUrl,
    this.onHeart,
    this.heartLiked = false,
  });

  /// The tray's default ❤️ like (see RealmojiTray.onHeart). Null hides it.
  final VoidCallback? onHeart;
  final bool heartLiked;

  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;

  /// Forwarded straight to [PostReactionButton] — see its own doc.
  final String? mySelfieUrl;

  /// Toggles [showTray] on the caller's state (PostReactions.openReactionTray).
  final VoidCallback onTap;

  /// Closes the tray (PostReactions.closePresetTray) — used by the new
  /// outside-tap/scroll dismiss barrier below, distinct from [onTap] since
  /// that one only ever OPENS (openReactionTray always sets true, it isn't
  /// a toggle). Calling [onTap] again from a dismiss path would be a no-op
  /// (setState to the same true value), which is exactly what silently
  /// broke this before — the tray would stay dismissed but the caller's own
  /// showTray bookkeeping would still read true, and next tap read the
  /// value as unchanged and never came back.
  final VoidCallback onClose;

  /// Whether the tray should currently be visible — this widget reacts to
  /// this flag changing (didUpdateWidget) to insert/remove its OverlayEntry,
  /// rather than owning the boolean itself, so it stays in sync with the
  /// same PostReactions.showPresetTray state every other tray consumer uses.
  final bool showTray;

  final ReactionPresetCategory category;
  final ValueChanged<ReactionPreset> onSelect;

  /// Old preset-tray "+ add new" — unused by RealmojiTray (see _show()
  /// below), kept only so this constructor's shape doesn't force a change
  /// at both existing card call sites. See PostReactions.openAddPresetFlow's
  /// own doc.
  final VoidCallback onAddNew;

  /// RealmojiTray's onCaptureNeeded — a tapped slot with no saved selfie
  /// yet routes here instead of onSelect.
  final ValueChanged<RealmojiType> onCaptureRealmoji;

  final double size;

  /// Forwarded straight to the wrapped [PostReactionButton] — see its own
  /// doc comments. The GlobalKey below measures whatever box that button
  /// ends up rendering, so the floating tray still anchors correctly
  /// regardless of which style/size is in play.
  final double? width;
  final double? height;
  final TrayIconVisualStyle style;

  @override
  State<PostReactionCorner> createState() => _PostReactionCornerState();
}

class _PostReactionCornerState extends State<PostReactionCorner> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  // Closes the tray when the enclosing feed scrolls — see
  // _PersonalPostCardState's identical pattern/doc for why Scrollable.of
  // (not a NotificationListener) is the right tool for a descendant widget
  // reacting to its ancestor Scrollable.
  ScrollPosition? _scrollPosition;

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
    if (widget.showTray) widget.onClose();
  }

  @override
  void didUpdateWidget(PostReactionCorner old) {
    super.didUpdateWidget(old);
    // Deferred to a post-frame callback — didUpdateWidget runs DURING the
    // enclosing BuildOwner.buildScope() pass (e.g. the one triggered by
    // PostReactions.openReactionTray's setState), and Overlay.insert /
    // OverlayEntry.remove / OverlayEntry.markNeedsBuild all call
    // setState()/markNeedsBuild() on the Overlay element — which is NOT a
    // descendant of whatever's currently being built here, so doing it
    // synchronously throws "setState() or markNeedsBuild() called during
    // build" every time (100% reproducible on any tap of the reaction
    // badge, not a race — see the framework's own assertion message for
    // why only descendants may be dirtied mid-build). Scheduling it for
    // right after the current frame is the standard fix for this exact
    // class of bug.
    if (widget.showTray != old.showTray) {
      final show = widget.showTray;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (show) {
          _show();
        } else {
          _hide();
        }
      });
    } else if (widget.showTray) {
      // Tray stayed open across a rebuild (e.g. a reaction summary refresh)
      // — refresh its content in place rather than leaving stale callbacks
      // bound to the old widget.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entry?.markNeedsBuild();
      });
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onAncestorScroll);
    _hide();
    super.dispose();
  }

  void _show() {
    _hide();
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayState = Overlay.maybeOf(context);
    if (box == null || overlayState == null) return;
    final topLeft = box.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.of(overlayContext).size;
        return Stack(
          children: [
            // Outside-tap dismiss barrier — true full-screen here (unlike
            // the live dropdown's per-card barrier) since this IS already
            // an Overlay entry painting above the entire app, not just one
            // card. Painted first so the tray itself (below, on top) still
            // receives its own taps.
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              right: screen.width - (topLeft.dx + box.size.width),
              bottom: screen.height - topLeft.dy + 10,
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  // Extra drop shadow: ReactionPresetTray's own frosted-glass
                  // look is tuned for floating over a photo — here it floats
                  // over whatever's behind the card (often the plain feed
                  // background), so a bit of contrast is added underneath
                  // without touching that shared widget's own styling.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: RealmojiTray(
                    category: widget.category,
                    onSelect: widget.onSelect,
                    onCaptureNeeded: widget.onCaptureRealmoji,
                    onHeart: widget.onHeart,
                    heartLiked: widget.heartLiked,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlayState.insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return PostReactionButton(
      key: _buttonKey,
      size: widget.size,
      width: widget.width,
      height: widget.height,
      style: widget.style,
      allowFaceReactions: widget.allowFaceReactions,
      myFaceReaction: widget.myFaceReaction,
      myEmoji: widget.myEmoji,
      uploading: widget.uploading,
      onTap: widget.onTap,
      mySelfieUrl: widget.mySelfieUrl,
    );
  }
}

/// The bell (per-post notification subscribe) that used to live at the
/// start of this row is gone — per this card family's own long-standing
/// doc comment ("no per-post bell — anywhere on this card, ever... a
/// single page-level bell now", see PhotoPostCard), the bell was only ever
/// meant to be that one page-level control (MainShell), not a per-card
/// one. It was still rendering here; removed. What's left is only the
/// Friends/Everyone reaction-library corner control, so on the Anonymous
/// feed (allowFaceReactions: false) this whole row now renders nothing —
/// see PhotoPostCard/TextPostCard's call sites, which skip wrapping this
/// in a Padding at all in that case so no blank reserved space is left
/// where the bell used to sit.
class PostTopControlsRow extends StatelessWidget {
  const PostTopControlsRow({
    super.key,
    required this.allowFaceReactions,
    required this.myFaceReaction,
    required this.myEmoji,
    required this.uploadingReaction,
    required this.onReactionTap,
    required this.onReactionClose,
    required this.showReactionTray,
    required this.reactionCategory,
    required this.onReactionSelect,
    required this.onReactionAddNew,
    required this.onReactionCaptureRealmoji,
  });

  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploadingReaction;
  final VoidCallback onReactionTap;
  final VoidCallback onReactionClose;
  final bool showReactionTray;
  final ReactionPresetCategory reactionCategory;
  final ValueChanged<ReactionPreset> onReactionSelect;
  final VoidCallback onReactionAddNew;
  final ValueChanged<RealmojiType> onReactionCaptureRealmoji;

  @override
  Widget build(BuildContext context) {
    // Friends/Everyone only — this is a card-LAYOUT decision, not a
    // capability one: Anonymous posts render NO top-right reaction
    // control at all, but they DO get the same PostReactionCorner
    // (preset tray, plain emoji, add-new) — just instantiated at the
    // bottom-right image notch instead (see each card's own tray-icon
    // overlay in photo_post_card.dart/text_post_card.dart).
    if (!allowFaceReactions) return const SizedBox.shrink();
    return Row(
      children: [
        const Spacer(),
        PostReactionCorner(
          allowFaceReactions: allowFaceReactions,
          myFaceReaction: myFaceReaction,
          myEmoji: myEmoji,
          uploading: uploadingReaction,
          onTap: onReactionTap,
          onClose: onReactionClose,
          showTray: showReactionTray,
          category: reactionCategory,
          onSelect: onReactionSelect,
          onAddNew: onReactionAddNew,
          onCaptureRealmoji: onReactionCaptureRealmoji,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Persona icon — the anon persona photo (Profile > Anon persona photo), a
// clean plain circle with a subtle border — no glow/tier-ring treatment.
// Never the real profile photo; a null url falls back to a plain silhouette
// glyph rather than initials, since initials can hint at a real name. [score]
// is kept on the API even though nothing currently reads it, in case a
// future compact status signal wants to reuse this slot without a call-site
// change.
// ---------------------------------------------------------------------------

class PersonaPhoto extends StatelessWidget {
  const PersonaPhoto({
    super.key,
    required this.photoUrl,
    required this.score,
    this.size = kSize,
    this.ringColor,
    this.ringWidth = 1,
  });
  final String? photoUrl;
  final int score;

  static const double kSize = 30;

  /// Override the default 30px size — used by PhotoPostCard's pixel-exact
  /// avatar-notch geometry, which fits the avatar to a specific traced
  /// radius rather than this default.
  final double size;

  /// Null keeps the default thin black-alpha border. PhotoPostCard's
  /// pixel-exact geometry instead passes solid white here — the notch cut
  /// into the image's top edge was traced assuming a WHITE ring creates
  /// that visual gap (see pixel_exact_post_card_clipper.dart), so a
  /// mismatched ring color would look inconsistent with the cut shape.
  final Color? ringColor;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFEFEFEF),
        border: Border.all(
          color: ringColor ?? Colors.black.withValues(alpha: 0.12),
          width: ringWidth,
        ),
      ),
      child: ClipOval(
        child: photoUrl == null
            ? Center(
                child: Icon(
                  Icons.theater_comedy_outlined,
                  color: const Color(0xFF999999),
                  size: size * 0.5,
                ),
              )
            : CachedNetworkImage(
                memCacheWidth: 1080,
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const SizedBox.shrink(),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    Icons.theater_comedy_outlined,
                    color: const Color(0xFF999999),
                    size: size * 0.5,
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction-entry badge — the single, dedicated affordance for reacting to
// a post, BeReal-style. Sits beside the persona icon — near it, but with a
// deliberate gap (see each card's _kEntryBadgeGap) so it reads as its OWN
// distinct, clearly-tappable button rather than a piece of the avatar — on
// both PhotoPostCard (floating on the image, just right of the dipped
// persona icon) and TextPostCard (directly in the identity row, no image to
// float on) — the SAME entry point into the SAME reaction flow as the
// bottom-right TopActionIcons heart, just closer to hand for a faster tap.
// Both read/write the same PostReactions-mixin state, so reacting via
// either stays in sync automatically.
//
// Styled deliberately heavier than a faint outline glyph — solid dark fill,
// thin light border, small drop shadow — so it holds its own visually
// against any photo behind it, the way BeReal's own add-reaction button
// does, instead of disappearing next to the persona icon.
//
// Idle: a small glyph — camera for feeds that allow face reactions
// (Friends/Everyone), add-reaction for the Anonymous feed (emoji-only). A
// tap no longer jumps straight into a fresh camera capture — it opens the
// quick-pick tray of the viewer's own saved reaction PRESETS instead (see
// PostReactions.openReactionTray + ReactionPresetTray, reaction_preset_tray.
// dart); a preset's own "+ add new" option is what reaches the camera now.
// Uploading: a small spinner, shown while applying a selected preset (or,
// via the tray's add flow, while a freshly captured selfie is being saved).
// Reacted: the glyph is replaced by a tiny thumbnail of the viewer's own
// reaction — their selfie (face reactions) or their emoji (Anonymous) —
// reusing the same circular-thumbnail language ReactionRow uses for
// everyone else's reactions below the image, just scaled down to fit a
// corner badge instead of a full row entry.
// ---------------------------------------------------------------------------

class ReactionEntryBadge extends StatelessWidget {
  const ReactionEntryBadge({
    super.key,
    required this.size,
    required this.allowFaceReactions,
    required this.myFaceReaction,
    required this.myEmoji,
    required this.uploading,
    required this.onTap,
    this.idleIcon,
    this.onLongPress,
  });

  final double size;
  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;
  final VoidCallback onTap;

  /// Overrides the idle-state glyph (camera / add-reaction). Callers that
  /// want their own brand mark here instead of the generic default — e.g.
  /// PhotoPostCard's bottom-notch placement — pass this; leave null to keep
  /// the default camera/add-reaction icon.
  final IconData? idleIcon;

  /// Optional faster/alternate path (e.g. PhotoPostCard wires this to the
  /// plain quick-emoji picker, so that flow stays reachable even where the
  /// badge's main tap opens the preset tray instead).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Solid dark fill (not the card's own surface color) + a light
          // border is what makes this read as a distinct, floating,
          // tappable button rather than a faint attached icon — it needs
          // to hold up against bright photo content behind it, same as
          // BeReal's own add-reaction button.
          color: Colors.black.withValues(alpha: 0.78),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    final iconSize = size * 0.5;
    if (uploading) {
      return SizedBox(
        width: iconSize * 0.75,
        height: iconSize * 0.75,
        child: const CircularProgressIndicator(
          strokeWidth: 1.75,
          color: Colors.white,
        ),
      );
    }
    if (allowFaceReactions && myFaceReaction != null) {
      return ClipOval(
        child: CachedNetworkImage(
          memCacheWidth: 1080,
          imageUrl: myFaceReaction!.photoUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Icon(
            Icons.face_retouching_natural,
            size: iconSize,
            color: Colors.white,
          ),
        ),
      );
    }
    if (!allowFaceReactions && myEmoji != null) {
      return Text(myEmoji!, style: TextStyle(fontSize: iconSize));
    }
    return Icon(
      idleIcon ??
          (allowFaceReactions
              ? Icons.camera_alt_rounded
              : Icons.add_reaction_rounded),
      size: iconSize,
      color: Colors.white,
    );
  }
}

// ---------------------------------------------------------------------------
// Branch/department tag — small ghosted pill (e.g. "CSE"), part of the
// identity row beside the persona icon.
// ---------------------------------------------------------------------------

class BranchTag extends StatelessWidget {
  const BranchTag({super.key, required this.branch});
  final String branch;

  @override
  Widget build(BuildContext context) {
    // Sits directly on the photo (top-right corner), not the card's own
    // background — a dark chip + white text reads reliably regardless of
    // how bright or dark that particular photo is, the same reasoning
    // ReactionEntryBadge uses for its own dark fill.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        branch,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WordSafeText — like Text with maxLines + TextOverflow.ellipsis, except
// the truncation only ever falls on a word boundary. Flutter's built-in
// TextOverflow.ellipsis clips at the pixel/character level once the text
// no longer fits, which can (and does) cut mid-word. This lays the text out
// with a TextPainter at [maxWidth]; if it overflows [maxLines], it finds
// where the last visible line ends, backs up to the previous space (never
// a partial word), and appends "…" to that shorter, already-fitting
// prefix — rather than iteratively re-testing "words + ellipsis" candidates
// against maxLines (which can itself shift line-wrapping in ways that
// don't match the final rendered Text exactly).
// ---------------------------------------------------------------------------

class WordSafeText extends StatelessWidget {
  const WordSafeText(
    this.text, {
    super.key,
    required this.style,
    required this.maxLines,
    required this.maxWidth,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);

    if (!painter.didExceedMaxLines) {
      return Text(text, style: style);
    }

    // Locate the last visible character (bottom-right of the clipped,
    // maxLines-tall layout), then walk back to the previous space so the
    // cut never lands mid-word.
    final endPosition = painter.getPositionForOffset(
      Offset(maxWidth, painter.height - 1),
    );
    var cutoff = endPosition.offset.clamp(0, text.length);
    while (cutoff > 0 && text[cutoff - 1] != ' ') {
      cutoff--;
    }
    final truncated =
        (cutoff > 0
                ? text.substring(0, cutoff)
                : text.substring(0, endPosition.offset))
            .trimRight();

    return Text(truncated.isEmpty ? '…' : '$truncated…', style: style);
  }
}

// ---------------------------------------------------------------------------
// GhostPromptBlock — the ghost prompt question the poster was replying to,
// small and emphasized, with their written answer/caption directly below
// it at full, readable contrast. Sits beside the persona icon on both
// cards. No accent bar — a plain stacked text column.
// ---------------------------------------------------------------------------

class GhostPromptBlock extends StatelessWidget {
  const GhostPromptBlock({
    super.key,
    required this.question,
    this.answer,
    required this.maxWidth,
    this.questionOpacity = 1.0,
  });

  final String question;
  final String? answer;
  final double maxWidth;

  /// Fades ONLY the question — the answer (the poster's own typed caption)
  /// always renders at full opacity regardless of this value. Used by
  /// PhotoPostCard's scroll-reveal: once a post is fully focused the prompt
  /// question disappears, but the caption (the only text a focused post is
  /// allowed to show) stays visible.
  final double questionOpacity;

  @override
  Widget build(BuildContext context) {
    final answerText = answer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: questionOpacity,
          child: WordSafeText(
            question,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111111),
              height: 1.3,
            ),
            maxLines: 2,
            maxWidth: maxWidth,
          ),
        ),
        if (answerText != null && answerText.isNotEmpty) ...[
          const SizedBox(height: 3),
          // Normal, high-contrast caption color — this is the poster's own
          // written text and needs to read clearly against the white card,
          // not fade into a faint ghost like the (already-dim) prompt.
          WordSafeText(
            answerText,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1C1C1C),
              height: 1.3,
            ),
            maxLines: 4,
            maxWidth: maxWidth,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top action icons — reaction (heart) + ping ONLY, per spec. Comment lives
// in its own row (CommentRow) below; face-reaction thumbnails live in their
// own BeReal-style row below the image (see photo_post_card.dart) — neither
// is bundled into this cluster anymore. Thin outline icons, monochrome
// except the reacted heart (colored). [iconShadows] is for use over
// arbitrary photo content (PhotoPostCard overlays these directly on the
// image per spec, and the image itself must stay full-opacity/undimmed —
// no scrim — so legibility comes from a glyph drop-shadow instead of
// darkening the photo).
// ---------------------------------------------------------------------------

const Color kClusterGray = Color(0xFF8E8E93);
const double kClusterIconSize = 18;
const double kClusterGap = 14;

class TopActionIcons extends StatelessWidget {
  const TopActionIcons({
    super.key,
    required this.liked,
    required this.likeCount,
    required this.uploadingFaceReaction,
    required this.onReactionTap,
    required this.onReactionLongPress,
    required this.onPingTap,
    this.iconColor,
    this.iconShadows,
  });

  final bool liked;
  final int likeCount;
  final bool uploadingFaceReaction;
  final VoidCallback onReactionTap;
  final VoidCallback? onReactionLongPress;

  final VoidCallback onPingTap;

  /// Defaults to white-on-scrim (for use over media); pass kClusterGray
  /// explicitly when placing these over a plain card background instead.
  final Color? iconColor;

  /// Optional drop-shadow so the glyphs stay legible over bright photo
  /// content without needing to dim the image itself.
  final List<Shadow>? iconShadows;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Colors.white.withValues(alpha: 0.90);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlainIconButton(
          icon: Icons.send_outlined,
          onTap: onPingTap,
          color: color,
          shadows: iconShadows,
        ),
        const SizedBox(width: kClusterGap),
        _HeartTapTarget(
          liked: liked,
          count: likeCount,
          uploading: uploadingFaceReaction,
          onTap: onReactionTap,
          onLongPress: onReactionLongPress,
          color: color,
          shadows: iconShadows,
        ),
      ],
    );
  }
}

class _HeartTapTarget extends StatelessWidget {
  const _HeartTapTarget({
    required this.liked,
    required this.count,
    required this.uploading,
    required this.onTap,
    required this.onLongPress,
    this.color = kClusterGray,
    this.shadows,
  });

  final bool liked;
  final int count;
  final bool uploading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: uploading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: kClusterIconSize,
                  color: liked ? AppColors.errorRed : color,
                  shadows: shadows,
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: liked ? AppColors.errorRed : color,
                      shadows: shadows,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PlainIconButton extends StatelessWidget {
  const _PlainIconButton({
    required this.icon,
    required this.onTap,
    this.color = kClusterGray,
    this.shadows,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    // Padding pads the tappable area well past the glyph's own 18px box —
    // a bare Icon-sized GestureDetector is an easy-to-miss target on a real
    // finger, which reads as "the button does nothing" even though the
    // handler itself is wired correctly.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(
          icon,
          size: kClusterIconSize,
          color: color,
          shadows: shadows,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PostPingButton — the ping action, now rendered BELOW the post (in the
// reaction+comment action row) rather than overlaid on the image. Same
// light-outline circular language as PostBellButton/PostReactionButton so
// it reads as one consistent family of below-post controls.
// ---------------------------------------------------------------------------

class PostPingButton extends StatelessWidget {
  const PostPingButton({
    super.key,
    required this.onTap,
    // §2: Ping button 34dp circle (was 28). Safe to default here — the
    // Anon feed's own tray call (photo_post_card.dart) always passes an
    // explicit width/height override for its notch geometry, so only
    // Friends-feed callers (PersonalPostCard, GroupPostCard) that rely on
    // this default are affected.
    this.size = 34,
    this.width,
    this.height,
    this.style = TrayIconVisualStyle.surface,
  });

  final VoidCallback onTap;
  final double size;

  /// Overrides [size] for a non-square box (the tray's glyph style is
  /// 19×20, not square) — null on both falls back to [size] on both axes,
  /// unchanged from before this param existed.
  final double? width;
  final double? height;

  /// [TrayIconVisualStyle.glyph] renders the spec's white-outline stick
  /// figure (post_card_tray_icons.dart) with no extra container — used
  /// only by PhotoPostCard's tray (Anonymous feed). TextPostCard stays on
  /// the default [TrayIconVisualStyle.surface] look below, untouched.
  final TrayIconVisualStyle style;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;

    // Unified across every feed (Anonymous, Friends/solo, Group) to the same
    // waving-hand glyph the group card's own Wave button uses (_WaveButton,
    // design_group_card.dart) — explicit request: "the reactions ping
    // symbol to the waving hand as it is in group posts apply it to anon and
    // friends feed as such". Replaces the earlier custom-painted glyphs
    // (StickFigureGlyphPainter / PingRingGlyphPainter, post_card_tray_icons.
    // dart) — both left defined but now unused, not deleted, since removing
    // them is outside this fix's scope.
    if (style == TrayIconVisualStyle.glyph) {
      return TrayHitTarget(
        width: w,
        height: h,
        onTap: onTap,
        child: Center(
          child: Icon(
            Icons.waving_hand_outlined,
            size: math.min(w, h) * 0.8,
            color: const Color(0xFF2A2A2E),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF131315),
        ),
        child: Icon(
          Icons.waving_hand_outlined,
          size: math.min(w, h) * 0.48,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comment row — its own row below the card's content (not overlaid).
// Instagram-style "View all N comments" summary chosen over a bare count
// badge: it doubles as the tap target into the existing comment sheet and
// reads cleaner than a raw number. No timestamp — this app dropped those
// from the design entirely.
// ---------------------------------------------------------------------------

class CommentRow extends StatelessWidget {
  const CommentRow({
    super.key,
    required this.commentCount,
    required this.onCommentTap,
  });

  final int commentCount;
  final VoidCallback? onCommentTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
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
    );
  }
}

// ---------------------------------------------------------------------------
// LightSurfaceBox — flat light-mode substitute for GlassBox (core/glass.dart)
// wherever a post card needs a "distinct surface" wrapper. GlassBox is a
// white-alpha + backdrop-blur treatment built for a dark page background —
// on the Anonymous feed's white background it would be nearly invisible
// (a near-white tint over white), and there's nothing interesting behind it
// on a flat white page to blur anyway. Same padding/borderRadius shape as
// GlassBox so it drops in at the same call sites.
// ---------------------------------------------------------------------------

class LightSurfaceBox extends StatelessWidget {
  const LightSurfaceBox({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Live presence — "N here" pill + dropdown, per design-refs/
// design_handoff_post_card_feed 2/README.md Widget A. Shared by
// PersonalPostCard (post_card.dart) and GroupPostCard (group_post_cards/)
// so both feed treatments show the exact same widget, per the parity ask.
//
// Backed by PresenceService / the live `post_presence` table (see
// supabase/migrations/20260905000000_post_presence.sql) — previously this
// was demoLivePresence(), a hash-seeded FAKE name generator with no backend
// at all. Every caller now loads real presence via
// PresenceService.instance.fetchPresence(postId) and maps it through
// PresenceUser.fromEntry below.
// ---------------------------------------------------------------------------

class PresenceUser {
  const PresenceUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastSeenAt,
    required this.isPinned,
    this.viewedOnly = false,
    this.notSeen = false,
  });

  factory PresenceUser.fromEntry(PresenceEntry e) => PresenceUser(
    id: e.userId,
    name: e.name,
    avatarUrl: e.avatarUrl,
    lastSeenAt: e.lastSeenAt,
    isPinned: e.isPinned,
    viewedOnly: e.viewedOnly,
    notSeen: e.notSeen,
  );

  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime lastSeenAt;

  /// Sorts first in LivePresenceDropdown — see PresenceEntry.isPinned.
  final bool isPinned;

  /// See PresenceEntry.viewedOnly's own doc — a pinned person who has
  /// opened this post but has no live/recent presence row. Drives the
  /// third "PINNED · SEEN" section in LivePresenceDropdown, which never
  /// claims this person is or was "here" the way the other two sections do.
  final bool viewedOnly;

  /// See PresenceEntry.notSeen — a pinned person who has NOT opened this
  /// post. Drives the fourth "PINNED · NOT SEEN" section. Their
  /// [lastSeenAt] is epoch 0 and must never be rendered as a time.
  final bool notSeen;

  /// Whether this person has opened the post at all, by any of the three
  /// routes that can put them in the list. The pill's "N seen" count is
  /// this, not [present.length] — see LivePresencePill.
  bool get hasSeen => !notSeen;

  /// Drives the HERE NOW / LAST 3 HOURS split in LivePresenceDropdown — see
  /// PresenceEntry.isHereNow's own doc for the same 2-minute cutoff.
  /// Always false for [viewedOnly] and [notSeen], regardless of
  /// [lastSeenAt].
  bool get isHereNow =>
      !viewedOnly &&
      !notSeen &&
      DateTime.now().difference(lastSeenAt) < const Duration(minutes: 2);
}

class LivePresencePill extends StatelessWidget {
  const LivePresencePill({
    super.key,
    required this.present,
    required this.onTap,
    this.compact = false,
    this.maxAvatars = 3,
    this.rightPadding,
    this.avatarsOnly = false,
  });
  final List<PresenceUser> present;
  final VoidCallback onTap;

  /// Faces only — no label text, no status dot, no pill chrome.
  ///
  /// A shared (Duo) post's byline carries TWO usernames, and the full
  /// pill's "not seen yet" / "N here" label ate enough width that both names
  /// could not fit — the header ellipsised to "abisheksdpatel &..." with the
  /// partner's name never visible at all. Explicit instruction: "replace
  /// this with only the two circles". The faces still carry the same
  /// information the label restated, and the pill stays tappable, so nothing
  /// is lost but the words.
  final bool avatarsOnly;

  /// Group cards use a smaller variant per FEED_IMPLEMENTATION_SPEC.md §3.2:
  /// height 29 (was 34), avatar cluster 18px/-7 overlap (was 22/-9), dot 7px
  /// (was 8), font-size 11.5/w800 (was 13/w700), and a different cluster
  /// palette (#e8dfd6/#cfc6dd/#a79bbf vs solo's #b9ad97/#9db29a/#a79bbf).
  final bool compact;

  /// How many overlapping avatars the cluster draws (the "N here" count text
  /// always reflects the true [present.length], regardless). DesignSoloCard
  /// caps this at 2 to reclaim width for its byline's username — see that
  /// card's own header-layout comment.
  final int maxAvatars;

  /// Overrides the pill's default right-side padding (5/13 compact/normal).
  /// Same DesignSoloCard width-reclaim as [maxAvatars].
  final double? rightPadding;

  @override
  Widget build(BuildContext context) {
    // Nobody else has been here yet. A bare "0 here" is still never shown —
    // but hiding the pill outright made the post look like it had no
    // presence surface at all. It says "only you" instead, which is what a
    // zero actually means here: the count deliberately excludes the viewer
    // (see PresenceService.fetchPresence's own self-exclusion), so zero
    // others means you're the only one who has been on it.
    // TAPPABLE even here. This used to return a bare Container with no
    // gesture detector, so in the one state where the panel has something
    // genuinely useful to say — "none of your pinned people has opened this
    // yet" — the pill was the only one on the card that did not respond to
    // a tap at all. Reported as "clicking on the presence pill is still
    // showing only you": the dropdown was never opening.
    // Faces-only (Duo and group posts) stays faces-only when empty too: one
    // neutral circle in the same slot. It used to fall back to the full
    // "only you"/"not seen yet" pill here, so while presence loaded — and
    // every time a card was rebuilt on scroll — the OLD pill flashed up and
    // then swapped to faces ("changing while scrolling, showing the older
    // version").
    if (present.isEmpty && avatarsOnly) {
      final size = compact ? 18.0 : 22.0;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF16151A),
          ),
          child: ClipOval(
            child: ColoredBox(
              color: const Color(0xFF2E2E33),
              child: Icon(
                Icons.person_rounded,
                size: size * 0.6,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      );
    }
    if (present.isEmpty) return _OnlyYouPill(compact: compact, onTap: onTap);

    // Live vs. merely-seen. PresenceService merges pinned people who OPENED
    // the post but have no live presence row (PresenceEntry.viewedOnly) into
    // the same list, so `present` is not all "here" — it used to be rendered
    // as though it were, which announced "1 here" with a glowing live dot
    // for someone who had simply looked at the post earlier and left.
    //
    // Explicit instruction: the pill must still show that pinned people
    // viewed it "even if no one is live here". So the entry stays, and only
    // the WORDING and the dot change to match what is actually true:
    //   - anyone genuinely live  -> "N here",  live cyan dot (unchanged)
    //   - only viewed-only left  -> "N seen",  dimmed dot, no glow
    //   - anyone genuinely live   -> "N here",      live cyan dot
    //   - only viewed-only left    -> "N seen",      dimmed dot, no glow
    //   - only pinned-not-seen     -> "not seen yet", dimmed dot
    //
    // Both counts exclude PresenceUser.notSeen. Those entries exist so the
    // dropdown can answer "which of my pinned people has seen this" — they
    // are, by definition, people who have NOT seen it, so counting them in
    // "N seen" would state the exact opposite of what they mean.
    final liveCount = present.where((p) => !p.viewedOnly && !p.notSeen).length;
    final seenCount = present.where((p) => p.hasSeen).length;
    final anyLive = liveCount > 0;
    final label = anyLive
        ? '$liveCount here'
        : (seenCount > 0 ? '$seenCount seen' : 'not seen yet');

    // Avatars follow the label: whoever the count is about goes in the
    // cluster first, so a pill reading "2 seen" never draws two faces that
    // both belong to people who haven't opened it.
    final ordered = [
      ...present.where((p) => p.hasSeen),
      ...present.where((p) => p.notSeen),
    ];
    final shown = ordered.take(maxAvatars).toList();
    final avatarSize = compact ? 18.0 : 22.0;
    final overlap = compact ? 7.0 : 9.0;
    final step = avatarSize - overlap;
    final dotSize = compact ? 7.0 : 8.0;
    final palette = compact
        ? const [Color(0xFFE8DFD6), Color(0xFFCFC6DD), Color(0xFFA79BBF)]
        : const [Color(0xFFB9AD97), Color(0xFF9DB29A), Color(0xFFA79BBF)];
    // See [avatarsOnly]: faces on their own, no pill chrome and no label,
    // so a two-username byline has the width it needs.
    if (avatarsOnly) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: avatarSize + (shown.length - 1).clamp(0, 3) * step,
          height: avatarSize,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * step,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    // Ring drawn as padding around an explicit ClipOval —
                    // the decoration's own clip rendered the photo as a
                    // rounded square inside the ring ("let the circles be a
                    // perfect circle").
                    padding: const EdgeInsets.all(1.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF16151A),
                    ),
                    child: ClipOval(
                      child: SizedBox.expand(
                        child: ColoredBox(
                          color: palette[i % palette.length],
                          child: _avatarPhoto(
                            shown[i].avatarUrl,
                            name: shown[i].name,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: compact ? 29 : 34,
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 5,
          0,
          rightPadding ?? (compact ? 11 : 13),
          0,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF8F4),
          borderRadius: BorderRadius.circular(compact ? 14.5 : 17),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: avatarSize + (shown.length - 1).clamp(0, 3) * step,
              height: avatarSize,
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * step,
                      child: Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette[i % palette.length],
                          border: Border.all(
                            color: const Color(0xFFFAF8F4),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: compact ? 6 : 7),
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Dimmed and un-glowed when nobody is actually live — the
                // glow is the "someone is on this right now" signal and
                // must not fire for a seen-only state.
                color: anyLive
                    ? Color(compact ? 0xFF22C9E8 : 0xFF37C9E6)
                    : const Color(0xFF2E2A22).withValues(alpha: 0.28),
                boxShadow: anyLive
                    ? [
                        BoxShadow(
                          color: Color(
                            compact ? 0xFF22C9E8 : 0xFF37C9E6,
                          ).withValues(alpha: 0.8),
                          blurRadius: 7,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            SizedBox(width: compact ? 6 : 7),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: compact ? 11.5 : 13,
                fontWeight: compact ? FontWeight.w800 : FontWeight.w700,
                color: Color(
                  compact ? 0xFF17171A : 0xFF2E2A22,
                ).withValues(alpha: anyLive ? 1.0 : 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "nobody else yet" state of [LivePresencePill] — same pill chrome and
/// metrics, no avatar cluster, and a dimmed dot instead of the live cyan
/// one, so it reads as "quiet" rather than "someone is here".
///
/// Not tappable: there is no presence list to open.
class _OnlyYouPill extends StatelessWidget {
  const _OnlyYouPill({required this.compact, this.onTap});

  final bool compact;

  /// See the call site in LivePresencePill — null only if a caller
  /// deliberately wants a non-interactive pill.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dotSize = compact ? 7.0 : 8.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: compact ? 29 : 34,
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 12,
          0,
          compact ? 11 : 13,
          0,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF8F4),
          borderRadius: BorderRadius.circular(compact ? 14.5 : 17),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2E2A22).withValues(alpha: 0.28),
              ),
            ),
            SizedBox(width: compact ? 6 : 7),
            Text(
              'only you',
              style: GoogleFonts.nunito(
                fontSize: compact ? 11.5 : 13,
                fontWeight: compact ? FontWeight.w800 : FontWeight.w700,
                color: Color(
                  compact ? 0xFF17171A : 0xFF2E2A22,
                ).withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Per the current Feed.dc.html "here now" panel (§3.3 of
// FEED_CANONICAL_SPEC.md) — REPLACES the old "LIVE" red-dot header + avatar
// rail with emoji badges. Solo anchors this at top:10/right:12/width:158/
// radius:13/z6; group anchors it at top:-4/right:14/width:160/radius:14/z9
// — same content, caller controls width/radius/position via the params
// below and its own Positioned wrapper.
// ---------------------------------------------------------------------------
// Ping prompt dropdown — §3.4: a compact anchored popover with 4 fixed
// prompts, replacing PostReactions.openPing's full bottom sheet
// (ping_prompt_sheet.dart) for the two design-faithful cards
// (design_solo_card.dart / design_group_card.dart) ONLY. The Anonymous
// feed's own notch ping trigger keeps opening the full sheet — a
// deliberately richer, separate flow, untouched.
//
// This app has no real ping-persistence backend anywhere (grepped: no
// PingService, no `pings` table write in ping_prompt_sheet.dart either —
// that sheet's own "Ping sent!" state is a local 1.5s animation with no
// network call). Tapping a prompt here is exactly as real/fake as the
// existing sheet: it closes and shows a toast, matching current app
// behavior rather than fabricating a persistence layer this session has no
// backend for.
// ---------------------------------------------------------------------------

const kPingPrompts = [
  ('👋', 'Say hi'),
  ('📸', 'Post a photo'),
  ('👀', "What's up?"),
  ('🔥', "That's fire"),
];

class PingPromptDropdown extends StatelessWidget {
  const PingPromptDropdown({super.key, required this.onSend});
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 186,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF141416).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, label) in kPingPrompts)
                _PingPromptRow(
                  icon: icon,
                  label: label,
                  onTap: () => onSend(label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PingPromptRow extends StatelessWidget {
  const _PingPromptRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 9),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
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
// More (⋯) menu — §3.6: Block / Report rows. No real per-post
// block-user/report-post backend exists anywhere in this codebase (grepped:
// nothing wires a post id to a report/block table) — [onBlock]/[onReport]
// are plain callbacks the caller can no-op or wire up later; this widget is
// UI-only.
// ---------------------------------------------------------------------------

class MoreMenuDropdown extends StatelessWidget {
  const MoreMenuDropdown({
    super.key,
    required this.onBlock,
    required this.onReport,
    this.onRemove,
  });
  final VoidCallback onBlock;
  final VoidCallback onReport;

  /// Non-null on a post that is the viewer's own: the menu is then ONE row,
  /// Remove — you don't block or report yourself (explicit request,
  /// 2026-10-07: "for the poster of the post, when clicked on three dots
  /// in the feed they can remove their own post from there also").
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRemove != null)
                _MoreMenuRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFFFF453A),
                  label: 'Remove',
                  labelColor: const Color(0xFFFF453A),
                  onTap: onRemove!,
                )
              else ...[
                _MoreMenuRow(
                  icon: Icons.block,
                  iconColor: Colors.white.withValues(alpha: 0.7),
                  label: 'Block',
                  labelColor: Colors.white.withValues(alpha: 0.85),
                  onTap: onBlock,
                ),
                _MoreMenuRow(
                  icon: Icons.outlined_flag,
                  iconColor: const Color(0xFFFF453A),
                  label: 'Report',
                  labelColor: const Color(0xFFFF453A),
                  onTap: onReport,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenuRow extends StatelessWidget {
  const _MoreMenuRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 9),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LivePresenceDropdown extends StatelessWidget {
  const LivePresenceDropdown({
    super.key,
    required this.present,
    this.width = 180,
    this.borderRadius = 13,
  });
  final List<PresenceUser> present;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final hereNow = present.where((u) => u.isHereNow).toList();
    // `!notSeen` is load-bearing: a not-seen entry is neither here-now nor
    // viewedOnly, so without it these people fell into BOTH this bucket and
    // the pinned-not-seen one below — listed twice, and the second listing
    // sat under a header ("LAST 3 HOURS") asserting recent presence for
    // someone who has not opened the post at all.
    final earlier = present
        .where((u) => !u.isHereNow && !u.viewedOnly && !u.notSeen)
        .toList();
    // Pinned people who have opened this post but have no live/recent
    // presence row at all — see PresenceUser.viewedOnly. A separate,
    // third section rather than folded into "LAST 3 HOURS": that label
    // asserts recent presence, which this explicitly is not — they may
    // have viewed it days ago. The section only ever contains pinned
    // people (viewedOnly is never set on anyone else).
    final pinnedSeen = present.where((u) => u.viewedOnly).toList();
    // Pinned people who have not opened the post at all — see
    // PresenceUser.notSeen. Listed last, and phrased as the absence it is,
    // so the panel answers "who of my pinned people has seen this" in full
    // rather than only naming the ones who happen to have shown up.
    final pinnedUnseen = present.where((u) => u.notSeen).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xFF161618).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          // The WHOLE body (both section headers + both row lists) scrolls
          // as one unit inside a single height cap — previously only the
          // inner row list scrolled while the "HERE NOW" header sat outside
          // it, which is why the panel still felt like it could grow
          // unbounded once a second section ("last 3 hours") was added.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (present.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No one here yet',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  if (hereNow.isNotEmpty) ...[
                    _sectionLabel('HERE NOW'),
                    for (var i = 0; i < hereNow.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _PresenceRow(user: hereNow[i]),
                    ],
                  ],
                  if (earlier.isNotEmpty) ...[
                    if (hereNow.isNotEmpty) const SizedBox(height: 10),
                    _sectionLabel('LAST 3 HOURS'),
                    for (var i = 0; i < earlier.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _PresenceRow(user: earlier[i]),
                    ],
                  ],
                  if (pinnedSeen.isNotEmpty) ...[
                    if (hereNow.isNotEmpty || earlier.isNotEmpty)
                      const SizedBox(height: 10),
                    _sectionLabel('PINNED · SEEN'),
                    for (var i = 0; i < pinnedSeen.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _PresenceRow(user: pinnedSeen[i]),
                    ],
                  ],
                  if (pinnedUnseen.isNotEmpty) ...[
                    if (hereNow.isNotEmpty ||
                        earlier.isNotEmpty ||
                        pinnedSeen.isNotEmpty)
                      const SizedBox(height: 10),
                    _sectionLabel('PINNED · NOT SEEN'),
                    for (var i = 0; i < pinnedUnseen.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _PresenceRow(user: pinnedUnseen[i]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.07 * 9.5,
        color: Colors.white.withValues(alpha: 0.42),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Seen pill + dropdown — the PROFILE-context replacement for the feed's
// "here" pill on the exact same card. Explicit instruction: "the seen pill
// ... shall be on each post the person has done, not on the profile [banner]
// ... it replaces the here pill in the profile section ... showing who all
// have seen it". So this is per-POST, same card, same corner as
// LivePresencePill — only the surface (profile vs feed) decides which of
// the two renders; see DesignSoloCard's `viewerSurface`.
//
// Backed by PostViewer/post_viewers (all-time, no window) rather than
// PresenceEntry/post_presence (3h, heartbeat) — "seen" is a permanent
// record, "here" is a live one. Deliberately its own dropdown rather than
// reusing LivePresenceDropdown: that widget's HERE NOW / LAST 3 HOURS
// labels are time-window claims that would be actively wrong here (a
// person who opened this post three days ago is not "in the last 3
// hours"). This one groups PINNED first, then everyone else, with no time
// bucketing at all — which is also exactly what the post_viewers() RPC
// already returns pre-sorted.
class SeenPill extends StatelessWidget {
  const SeenPill({
    super.key,
    required this.viewers,
    required this.onTap,
    this.compact = false,
    this.maxAvatars = 2,
    this.rightPadding,
    this.avatarsOnly = false,
  });

  final List<PostViewer> viewers;
  final VoidCallback onTap;
  final bool compact;
  final int maxAvatars;
  final double? rightPadding;

  /// Faces only — the same round-circles treatment the friends feed's
  /// LivePresencePill(avatarsOnly) gives Duo and group posts, instead of
  /// the white "7 seen" pill. Explicit request: the profile's seen pill
  /// should look like the feed's circles. Tap still opens the seen list.
  final bool avatarsOnly;

  Widget _facesOnly(List<PostViewer> shown) {
    final size = compact ? 18.0 : 22.0;
    final step = size - (compact ? 7.0 : 9.0);
    Widget ring(Widget child) => Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF16151A),
      ),
      child: ClipOval(child: SizedBox.expand(child: child)),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: shown.isEmpty
          ? ring(
              ColoredBox(
                color: const Color(0xFF2E2E33),
                child: Icon(
                  Icons.person_rounded,
                  size: size * 0.6,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            )
          : SizedBox(
              width: size + (shown.length - 1).clamp(0, 3) * step,
              height: size,
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * step,
                      child: ring(
                        ColoredBox(
                          color: const Color(0xFF3A3F52),
                          child: _avatarPhoto(
                            shown[i].avatarUrl,
                            name: shown[i].displayName,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Deliberately DOES show a bare 0, unlike LivePresencePill/here — "seen"
    // is a permanent record, and "0 seen" on a fresh post is a real,
    // meaningful answer (confirms the feature exists) rather than the
    // nothing-to-report case a live "0 here" would be. Explicit follow-up
    // after the "here" pill's own hide-at-0 rule was questioned for this
    // one specifically.
    // Two circles, the LATEST viewers (explicit request). The list itself
    // stays pinned-first for the dropdown; only the faces sort by time.
    final shown =
        ([...viewers]..sort((a, b) {
              final ta = a.viewedAt, tb = b.viewedAt;
              if (ta == null || tb == null) {
                return ta == tb ? 0 : (ta == null ? 1 : -1);
              }
              return tb.compareTo(ta);
            }))
            .take(maxAvatars)
            .toList();
    if (avatarsOnly) return _facesOnly(shown);
    final avatarSize = compact ? 18.0 : 22.0;
    final overlap = compact ? 7.0 : 9.0;
    final step = avatarSize - overlap;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: compact ? 29 : 34,
        padding: EdgeInsets.fromLTRB(
          compact ? 4 : 5,
          0,
          rightPadding ?? (compact ? 11 : 13),
          0,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF8F4),
          borderRadius: BorderRadius.circular(compact ? 14.5 : 17),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // No empty circle placeholder when there's nobody yet — the
            // icon + "0" below already says that on their own.
            if (shown.isNotEmpty) ...[
              SizedBox(
                width: avatarSize + (shown.length - 1).clamp(0, 3) * step,
                height: avatarSize,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * step,
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2A2A32),
                            border: Border.all(
                              color: const Color(0xFFFAF8F4),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _avatarPhoto(
                            shown[i].avatarUrl,
                            name: shown[i].displayName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : 7),
            ],
            // Matched to the ANON feed's own seen chip (_LivePresenceChip in
            // anon_feed_screen.dart) — explicit request: "this seen pill in
            // profile, change it to the seen pill design same as the anon
            // seen pill". That chip reads faces + a soft pulse dot + "N
            // seen" as words, so the eye glyph and the bare number are both
            // gone here rather than the two designs staying out of step.
            //
            // The pulse dot is the one piece deliberately NOT copied: on the
            // anon chip it sits beside a live-ish presence read, whereas
            // this list is a permanent seen record — a pulsing "active now"
            // dot next to someone who opened the post three days ago would
            // be asserting something untrue, which is the same reason this
            // pill never reused LivePresenceDropdown (see class doc).
            Text(
              '${viewers.length} seen',
              style: GoogleFonts.inter(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
                color: const Color(0xFF16151A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SeenDropdown extends StatelessWidget {
  const SeenDropdown({
    super.key,
    required this.viewers,
    this.width = 180,
    this.borderRadius = 13,
  });
  final List<PostViewer> viewers;
  final double width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // post_viewers() already orders pinned-first server-side; this split is
    // purely for the two section labels, not a re-sort.
    final pinned = viewers.where((v) => v.isPinned).toList();
    final rest = viewers.where((v) => !v.isPinned).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xFF161618).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (viewers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'No one has seen this yet',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  if (pinned.isNotEmpty) ...[
                    _seenSectionLabel('PINNED'),
                    for (var i = 0; i < pinned.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _SeenRow(viewer: pinned[i]),
                    ],
                  ],
                  if (rest.isNotEmpty) ...[
                    if (pinned.isNotEmpty) const SizedBox(height: 10),
                    _seenSectionLabel('SEEN'),
                    for (var i = 0; i < rest.length; i++) ...[
                      if (i > 0) const SizedBox(height: 7),
                      _SeenRow(viewer: rest[i]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seenSectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.07 * 9.5,
        color: Colors.white.withValues(alpha: 0.42),
      ),
    ),
  );
}

class _SeenRow extends StatelessWidget {
  const _SeenRow({required this.viewer});
  final PostViewer viewer;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: viewer.isPinned ? () => openProfile(context, viewer.userId) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2A2A32),
            ),
            clipBehavior: Clip.antiAlias,
            child: _avatarPhoto(viewer.avatarUrl, name: viewer.displayName),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              viewer.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
          if (viewer.isPinned) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.push_pin_rounded,
              size: 11,
              color: const Color(0xFF37C9E6).withValues(alpha: 0.85),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({required this.user});
  final PresenceUser user;

  @override
  Widget build(BuildContext context) {
    // A not-seen row is a real, tappable person — same row, just held back
    // visually so the panel reads at a glance as "these saw it, these
    // haven't" without needing the section header to carry that alone.
    final dim = user.notSeen;
    return GestureDetector(
      onTap: user.isPinned ? () => openProfile(context, user.id) : null,
      child: Opacity(
        opacity: dim ? 0.5 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2A2A32),
              ),
              clipBehavior: Clip.antiAlias,
              child: _avatarPhoto(user.avatarUrl, name: user.name),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (user.isPinned) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.push_pin_rounded,
                size: 11,
                color: const Color(0xFF37C9E6).withValues(alpha: 0.85),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

// ---------------------------------------------------------------------------
// Comment-card glyphs — ported literally from the live Feed.dc.html source
// (not generic Material icons, which don't match the design's actual
// shapes): the comment-toggle speech bubble (`M3.4 4.6h17.2v11.6H8.4L3.4
// 19.8z`, viewBox 24, stroke rgba(255,255,255,.4) width 2, linejoin round),
// its chevron (`M6 9l6 6 6-6`, viewBox 24, stroke rgba(255,255,255,.35)
// width 2.6 round), and the composer's send-plane (`M2.2 21.3 22.5 12 2.2
// 2.7l.1 7.3 12 1.9-12 2z`, viewBox 24, filled rgba(255,255,255,.55)) — the
// last one also fixes an explicit "own send button design, not the same as
// Anon's" request: this is this design's own precise glyph, distinct from
// anon_feed_v2's separate hand-rolled PaperPlanePainter.
// ---------------------------------------------------------------------------

class _ChatBubbleGlyphPainter extends CustomPainter {
  const _ChatBubbleGlyphPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(3.4, 4.6)
      ..lineTo(20.6, 4.6)
      ..lineTo(20.6, 16.2)
      ..lineTo(8.4, 16.2)
      ..lineTo(3.4, 19.8)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ChevronDownGlyphPainter extends CustomPainter {
  const _ChevronDownGlyphPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(6, 9)
        ..lineTo(12, 15)
        ..lineTo(18, 9),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChevronDownGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SendPlaneGlyphPainter extends CustomPainter {
  const _SendPlaneGlyphPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(2.2, 21.3)
      ..lineTo(22.5, 12)
      ..lineTo(2.2, 2.7)
      ..lineTo(2.3, 10.0)
      ..lineTo(14.3, 11.9)
      ..lineTo(2.3, 13.9)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SendPlaneGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Reactions overlay — bottom-left glass pill (avatar cluster + count) that
// toggles a horizontal reactor strip, per Widget C / "Reactions strip" in
// the same handoff doc. Shared by PersonalPostCard and GroupPostCard so
// tapping either opens the identical strip — same component, not a
// reimplementation per card family.
// ---------------------------------------------------------------------------

/// Bottom-left "reaction viewing" cluster — per the CURRENT Feed.dc.html
/// (confirmed against the live Claude Design fetch this session, which
/// supersedes the older vendored design-refs/Feed.dc.html this widget was
/// previously reverted to match): two 34dp overlapping avatars (-13dp
/// overlap) + a solid rgba(0,0,0,.5) count chip, NO glass/blur container —
/// unlike the old design's frosted 40dp pill. Parametrized so group's
/// collage layout (on-card, opaque black border, rgba(255,255,255,.1) chip)
/// and deck layout (30dp avatars) can reuse this exact shape instead of
/// duplicating it — see group_card_shared.dart call sites.
///
/// ⚠️ DO NOT reimplement the avatar overlap with a negative
/// `Container.margin` (e.g. `margin: EdgeInsets.only(left: -overlap)`).
/// Container asserts `margin.isNonNegative`, so that version throws
/// "Failed assertion: 'margin == null || margin.isNonNegative'" the moment
/// this pill renders — which tears down the card's entire photo overlay,
/// not just the pill.
///
/// It hid for a long time because the pill early-returns when
/// `totalCount <= 0`, and the `reactions` table was empty — so nothing ever
/// rendered it. It would have fired for real the first time any user
/// reacted to a post.
///
/// The Stack/Positioned build() below is the fix, and matches how
/// ReactorCluster (reactor_cluster.dart) and RealmojiReactorStack
/// (realmoji_reactor_stack.dart) already do overlapping avatars here.
///
/// NOTE FOR PARALLEL SESSIONS: this widget arrived as uncommitted work (it
/// is in neither checkpoint 7602482 nor e30bfda), so another working copy
/// may still hold the broken negative-margin version. Take THIS
/// implementation when reconciling, not that one.
class PostReactionsPill extends StatelessWidget {
  const PostReactionsPill({
    super.key,
    required this.reactors,
    required this.totalCount,
    required this.onTap,
    this.avatarSize = 34,
    this.overlap = 13,
    this.borderColor = const Color(0x8C000000), // rgba(0,0,0,.55)
    this.chipColor = const Color(0x80000000), // rgba(0,0,0,.5)
  });
  final List<LikeReactor> reactors;
  final int totalCount;
  final VoidCallback onTap;
  final double avatarSize;
  final double overlap;
  final Color borderColor;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 0) return const SizedBox.shrink();
    final shown = reactors.take(2).toList();
    final chipRadius = avatarSize / 2;
    // Overlap is done with a Stack, NOT a negative Container.margin —
    // Container asserts `margin.isNonNegative`, so the negative-margin
    // version this replaces threw the moment the pill actually rendered
    // (i.e. as soon as any post had a reaction) and took the card's whole
    // photo overlay down with it. Stack+Positioned is also what
    // ReactorCluster and RealmojiReactorStack already use for the same
    // overlapping-avatars effect.
    //
    // Geometry: avatar i sits at i*(avatarSize-overlap); the chip starts at
    // shown.length*(avatarSize-overlap), which lands exactly `overlap` short
    // of the last avatar's right edge — the same tuck the old margin gave.
    final step = avatarSize - overlap;
    final chipLeft = shown.isEmpty ? 0.0 : shown.length * step;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Non-positioned, so this child alone defines the Stack's size —
          // its left padding reserves the avatars' visible width.
          Padding(
            padding: EdgeInsets.only(left: chipLeft),
            child: Container(
              height: avatarSize,
              padding: const EdgeInsets.fromLTRB(17, 0, 10, 0),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(chipRadius),
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Text(
                '+$totalCount',
                style: GoogleFonts.inter(
                  fontSize: avatarSize >= 34 ? 13 : 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: ClipOval(
                  child: _avatarPhoto(shown[i].avatarUrl, name: shown[i].name),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-left reaction preview on every friends-feed card.
///
/// A deliberate copy of the Anon feed's own on-photo stack
/// (anon_feed_screen.dart's _OnPhotoReactionStack) — explicit instruction:
/// "I want the exact same mimicry in the friends feed, not something else".
/// Same 30px overlapping reactor circles, same dark count pill with the
/// chevron, same tokens (AnonFeedColors/AnonFeedType/ChevronRightPainter),
/// and the same "React" pill when nothing has been reacted yet rather than
/// vanishing ("if nobody has reacted let it be as reacted just like in anon
/// post").
///
/// Never fetches anything itself — both the faces and the count come from
/// the ReactionSummary the card has already loaded.
///
/// [onTap] now does real things (it didn't at first — "shall not open at
/// all" was the original instruction, superseded by "clicking on them open
/// up comment section... in the profile section" and "if they click on the
/// friends feed then there shall be a notification"): a feed card wires it
/// to a toast pointing at the profile, a profile/group-profile card wires
/// it to [showPostCommentsSheet]. Reactor identity still only ever reaches
/// the screen through that second path.
class ReactionPreviewChip extends StatelessWidget {
  const ReactionPreviewChip({
    super.key,
    required this.count,
    this.faces = const [],
    this.emojiCounts = const {},
    required this.onTap,
  });

  /// Total reactions on the post.
  final int count;

  final VoidCallback onTap;

  /// The reactors' RealMoji selfies. Empty falls back to emoji glyph
  /// circles, exactly as the anon stack does for pre-RealMoji reactions.
  final List<FaceReaction> faces;

  /// Plain emoji reactions, glyph -> count (`ReactionSummary.emojiCounts`).
  ///
  /// BUG FIX (reported with a screenshot of a bare "1 ›" pill and "give the
  /// preview, not just the number"): [faces] only ever holds RealMoji
  /// reactions, which are the ones carrying a photo. A plain emoji reaction
  /// lands in `totalEmojiCount` and contributes NOTHING to [faces] — so a
  /// post whose only reaction was an emoji had count = 1 and an empty
  /// faces list, and both render loops below drew nothing. The pill showed
  /// the number with no preview beside it.
  ///
  /// Passing the glyph map lets the chip draw those reactions too, so the
  /// preview is never empty while the count is non-zero.
  final Map<String, int> emojiCounts;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _content(),
    );
  }

  Widget _content() {
    if (count <= 0) {
      // BUMPED 24 -> 27: explicit follow-up to scale the reaction-viewer
      // chip up alongside the post frame, DP and ping/RealMoji buttons —
      // "relatively increase... the reaction viewer button as well".
      return Container(
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AnonFeedColors.countPillBg,
          borderRadius: BorderRadius.circular(13.5),
          border: Border.all(color: AnonFeedColors.hairlineCountPill),
        ),
        // "Reactions", not "React" — this is the entry point for VIEWING
        // who reacted, not a button that reacts. Explicit correction: "in
        // the bottom left there is a thing to view others reactions, it's
        // showing as React — change it to Reactions".
        child: Center(child: Text('Reactions', style: AnonFeedType.t7)),
      );
    }

    final withPhotos = faces
        .where((f) => f.photoUrl.isNotEmpty)
        .take(3)
        .toList();

    // Glyph fallback, in priority order: a RealMoji that somehow has no
    // photo, then plain emoji reactions. Deduped so two people reacting
    // with the same emoji draw one circle, not two identical ones — the
    // count pill beside it already carries "how many".
    final glyphs = <String>{
      for (final f in faces)
        if (f.photoUrl.isEmpty && f.emoji.trim().isNotEmpty) f.emoji,
      for (final e in emojiCounts.keys)
        if (e.trim().isNotEmpty) e,
    }.take(3).toList();

    // BUMPED 30 -> 34, same follow-up as the zero-count pill above.
    const chipSize = 34.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (withPhotos.isNotEmpty)
          for (var i = 0; i < withPhotos.length; i++)
            Transform.translate(
              offset: Offset(i == 0 ? 0 : -9.0 * i, 0),
              child: _PreviewFace(size: chipSize, face: withPhotos[i]),
            )
        else
          for (var i = 0; i < glyphs.length; i++)
            Transform.translate(
              offset: Offset(i == 0 ? 0 : -7.0 * i, 0),
              // BUMPED 24 -> 27, same follow-up as chipSize/the zero-count
              // pill above — the glyph-fallback circles for a plain emoji
              // reaction (no RealMoji photo) scale with everything else.
              child: Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AnonFeedColors.chipLight,
                  border: Border.all(
                    color: AnonFeedColors.chipRingWhite,
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      offset: Offset(0, 2),
                      blurRadius: 6,
                      color: Color(0x3D000000),
                    ),
                  ],
                ),
                // Black, not the inherited white: a text-style glyph (the
                // like ♥/❤ without its emoji variant) was white on this white
                // disc and vanished. Colour emoji ignore the colour.
                child: Center(
                  child: Text(
                    glyphs[i],
                    style: const TextStyle(fontSize: 13, color: Colors.black),
                  ),
                ),
              ),
            ),
        Transform.translate(
          offset: Offset(
            withPhotos.isNotEmpty
                ? -9.0 * withPhotos.length
                : -7.0 * glyphs.length,
            0,
          ),
          // BUMPED 24 -> 27, matching the zero-count pill above.
          child: Container(
            height: 27,
            padding: const EdgeInsets.only(left: 11, right: 8),
            decoration: BoxDecoration(
              color: AnonFeedColors.countPillBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnonFeedColors.hairlineCountPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count', style: AnonFeedType.t7),
                const SizedBox(width: 3),
                SizedBox(
                  width: 7,
                  height: 7,
                  child: CustomPaint(
                    painter: ChevronRightPainter(
                      color: const Color(0xBFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One reactor circle — the named-feed twin of the anon stack's
/// _ReactionFace1A, same ring, shadow and inset.
class _PreviewFace extends StatelessWidget {
  const _PreviewFace({required this.size, required this.face});

  final double size;
  final FaceReaction face;

  @override
  Widget build(BuildContext context) {
    final d = size - 3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AnonFeedColors.chipRingWhite,
                width: 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 2),
                  blurRadius: 6,
                  color: Color(0x3D000000),
                ),
              ],
            ),
          ),
          // A light blur on the feed preview (explicit request): enough to
          // see someone reacted with their face, not who — tap to find out.
          ClipOval(
            child: SizedBox(
              width: d,
              height: d,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                child: CachedNetworkImage(
                  memCacheWidth: 120,
                  imageUrl: face.photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ColoredBox(
                    color: AnonFeedColors.chipLight,
                    child: Center(
                      child: Text(
                        face.emoji,
                        style: TextStyle(fontSize: d * 0.42),
                      ),
                    ),
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

class PostReactionsStrip extends StatelessWidget {
  const PostReactionsStrip({
    super.key,
    required this.reactors,
    required this.totalCount,
  });
  final List<LikeReactor> reactors;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
            child: Text(
              'REALMOJIS · $totalCount',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08 * 9.5,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ),
          SizedBox(
            // 56 avatar + 7 gap + the name's own line box. 82 was a couple
            // of pixels short of what the 10.5pt label actually measures,
            // so this row rendered a yellow-and-black overflow stripe under
            // every RealMoji strip.
            height: 90,
            child: ScrollConfiguration(
              behavior: const _NoScrollbarBehavior(),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (var i = 0; i < reactors.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    _ReactorTile(reactor: reactors[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Plain selfie-colored circle, no emoji badge — per the current design's
// RealMoji rail (a literal selfie photo per reactor, not an
// avatar+separate-emoji combo the old "Reactions" strip used).
/// A compact, horizontally-scrollable "who reacted" panel, sized to sit as a
/// dropdown anchored above a card's bottom-left reactions pill rather than
/// as a full-width section below the photo (PostReactionsStrip's job).
///
/// Tapping a face opens that person's profile — same global routing every
/// other avatar in the Friends/Everyone feed uses.
class PostReactionsDropdown extends StatelessWidget {
  const PostReactionsDropdown({
    super.key,
    required this.reactors,
    required this.totalCount,
    this.maxWidth = 250,
  });

  final List<LikeReactor> reactors;
  final int totalCount;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (reactors.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
            color: const Color(0xFF161618).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 7),
                child: Text(
                  'REACTED · $totalCount',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.07 * 9,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ),
              SizedBox(
                // _MiniReactorTile is 42 (avatar) + 5 (gap) + ~13 (9pt
                // single-line label) = 60. Measured, not guessed: 52 here
                // overflowed by exactly 8px on device.
                height: 62,
                child: ScrollConfiguration(
                  behavior: const _NoScrollbarBehavior(),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < reactors.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _MiniReactorTile(reactor: reactors[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Poster-only "who reacted" section — item #1's replacement for the
/// public PostReactionsPill/PostReactionsDropdown pair. Rendered ONLY on
/// the post author's own profile (PostsList's showReactionsViewer flag),
/// never in any feed and never on someone else's profile: reacting stays
/// visible to everyone who can react, but seeing WHO reacted is now
/// author-only. Self-contained (owns its own expand state) so a caller
/// only has to drop it in, unlike the pill/dropdown pair it replaces.
class PostReactionsSection extends StatefulWidget {
  const PostReactionsSection({
    super.key,
    required this.reactors,
    required this.totalCount,
    this.onOpen,
  });

  final List<LikeReactor> reactors;
  final int totalCount;

  /// When set, tapping the REACTED header opens this instead of toggling
  /// the inline expander — used to send the tap into the post's comment
  /// section, where the reactor row lives alongside the replies.
  ///
  /// The inline expander it replaces showed the same faces in a horizontal
  /// strip with nothing else: no replies, and no way to reach them from
  /// there. Reported as reactions needing to "open in a row in comment
  /// section". Null keeps the original expand/collapse behaviour.
  final VoidCallback? onOpen;

  @override
  State<PostReactionsSection> createState() => _PostReactionsSectionState();
}

class _PostReactionsSectionState extends State<PostReactionsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Same "hide at zero" rule PostReactionsPill used, so a post with no
    // reactions yet shows nothing here rather than an empty header.
    if (widget.totalCount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The header is the faces themselves — overlapping reactor photos,
          // then the count, then the chevron. Explicit request: "in the
          // profile, view reactions shall be like [this] to view the real
          // emoji, not through the three dots."
          //
          // Showing the actual photos in the closed state is the point: a
          // RealMoji reaction IS a face, and "Reactions · 4" as a line of
          // text gave no reason to open it. The faces are also the reason
          // this can't live behind a "..." menu — a menu hides exactly the
          // thing worth seeing at a glance.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                widget.onOpen ?? () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.reactors.isNotEmpty) ...[
                  _ReactorFaceStack(reactors: widget.reactors),
                  const SizedBox(width: 9),
                ],
                // BUG FIX ("what does this do in the profile?"): with one
                // reactor this row was a lone avatar, a bare "1" and a
                // chevron — nothing said what the number counted, so it
                // read as an unexplained control. The label is always
                // present now, and says REACTED to match the wording the
                // anon feed's own reactions sheet already uses.
                Text(
                  'REACTED',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.07 * 9,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${widget.totalCount}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(width: 4),
                // Points the way the tap actually goes: a chevron DOWN for
                // the inline expander, a chevron RIGHT when the tap leaves
                // for the comment section instead (onOpen). A down-chevron
                // on a row that never expands promises the wrong thing.
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    widget.onOpen != null
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 62,
                child: ScrollConfiguration(
                  behavior: const _NoScrollbarBehavior(),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < widget.reactors.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _MiniReactorTile(reactor: widget.reactors[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactorTile extends StatelessWidget {
  const _ReactorTile({required this.reactor});
  final LikeReactor reactor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProfile(context, reactor.id),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _avatarPhoto(
                  reactor.displayPhotoUrl,
                  name: reactor.name,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              reactor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// BUG FIX (explicit report — comment rows "showing no dp at all"): the
/// no-photo fallback used to be a flat #17171B circle, which against the
/// comment card's own near-black surface was effectively invisible — a
/// commenter without a profile photo (very common: several real accounts
/// have profile_photo_url null) read as having no avatar rendered at all.
/// Falls back to their initial on a muted tint instead, the same
/// initial-glyph language group_card_shared.dart's Avatar already uses.
Widget _avatarPhoto(String? url, {String? name}) {
  if (url == null || url.isEmpty) return _avatarInitial(name);
  return CachedNetworkImage(
    memCacheWidth: 1080,
    imageUrl: url,
    fit: BoxFit.cover,
    errorWidget: (_, _, _) => _avatarInitial(name),
  );
}

Widget _avatarInitial(String? name) {
  final trimmed = (name ?? '').trim();
  final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  // Deterministic tint per name so the same person keeps the same colour
  // across every row they appear in.
  const palette = [
    Color(0xFF3A3F52),
    Color(0xFF4A3A52),
    Color(0xFF52463A),
    Color(0xFF3A5245),
    Color(0xFF523A44),
    Color(0xFF3A4752),
  ];
  final tint =
      palette[trimmed.isEmpty ? 0 : trimmed.hashCode.abs() % palette.length];
  return Container(
    color: tint,
    alignment: Alignment.center,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          initial,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    ),
  );
}

// Local-only demo posts (services/demo_content.dart's LocalPost, ids like
// "demo-post-8") aren't real Supabase rows — a real CommentService fetch
// against one of them always fails ("invalid input syntax for type uuid")
// and silently falls back to an empty list, so their comment card/sheet was
// untestable with real-looking content. This canned fallback (checked only
// when the real fetch comes back empty for one of these known local ids)
// makes the design visually verifiable without needing real backend rows.
bool _isLocalDemoPostId(String? postId) =>
    postId != null && postId.startsWith('demo-post-');

List<Comment> _demoFallbackComments() => [
  Comment(
    id: 'demo-c1',
    userId: 'demo_riley',
    name: 'riley_m',
    avatarUrl: null,
    body: 'this is so pretty, where is this??',
    createdAt: DateTime.now().subtract(const Duration(minutes: 22)),
  ),
  Comment(
    id: 'demo-c2',
    userId: 'demo_jordan',
    name: 'jordan_p',
    avatarUrl: null,
    body: 'golden hour hits different on the quad fr',
    createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
  ),
  Comment(
    id: 'demo-c3',
    userId: 'demo_maya',
    name: 'maya_k',
    avatarUrl: null,
    body: 'okay but the lighting 😭',
    createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
  ),
];

/// The comment composer's own identity-toggle avatar (real photo <->
/// anonymous), shared by both comment sheets in this file (PostCommentCard
/// and _CommentsSheetContent — see each's own `_isAnon` toggle). BUG FIX
/// (explicit report, with a screenshot of the exact symptom): both used to
/// render a flat decorative gradient in real-identity mode and a plain
/// theater-mask icon in anon mode — never the caller's own actual photo,
/// in either mode, regardless of whether one was set. Wired to real data
/// on both sides: [isAnon] true shows AnonPersonaService's persona photo
/// (users.anon_photo_url — the same one the anon feed's post cards show),
/// false shows the real profile photo (users.profile_photo_url — the same
/// one Friends-feed post cards show), each still falling back to its
/// original decorative treatment when nothing is set.
class _MyCommentAvatar extends StatefulWidget {
  const _MyCommentAvatar({required this.isAnon, required this.size});
  final bool isAnon;
  final double size;

  @override
  State<_MyCommentAvatar> createState() => _MyCommentAvatarState();
}

class _MyCommentAvatarState extends State<_MyCommentAvatar> {
  String? _realAvatarUrl;

  @override
  void initState() {
    super.initState();
    AnonPersonaService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadRealAvatar();
  }

  Future<void> _loadRealAvatar() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('profile_photo_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _realAvatarUrl = row?['profile_photo_url'] as String?);
    } catch (_) {
      // Leaves _realAvatarUrl null — falls back to the decorative gradient,
      // same as before this photo existed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.isAnon
        ? AnonPersonaService.instance.photoUrl
        : _realAvatarUrl;
    if (url == null || url.isEmpty) {
      return widget.isAnon
          ? Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2A2A2E),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.theater_comedy_outlined,
                size: widget.size * 0.52,
                color: const Color(0xFFCFCFD4),
              ),
            )
          : Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFB9AD97), Color(0xFFA79BBF)],
                ),
              ),
            );
    }
    return ClipOval(
      child: CachedNetworkImage(
        memCacheWidth: 1080,
        imageUrl: url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          width: widget.size,
          height: widget.size,
          color: const Color(0xFF2A2A2E),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comment card — header + preview rows + composer (identity-toggle avatar,
// placeholder text, send button), per the "Comment card" section of the
// same handoff doc. Shared by PersonalPostCard and GroupPostCard. Real
// fetch/post backed by CommentService (comment_service.dart) — the first
// real comment UI this app has had; previously every card only linked out
// to a detail screen with no comment UI of its own.
// ---------------------------------------------------------------------------

/// Opens the SAME comments sheet [PostCommentCard]'s own comment icon does
/// — reactor strip on top, comment list and composer below — from any tap
/// target, not just that card's own icon. Lets [ReactionPreviewChip] open it
/// directly on a profile or group profile, where reacting identity is
/// already allowed to show (see that widget's own doc).
///
/// [onPosted] refreshes whatever collapsed preview is showing under the
/// hood — omit it if the caller has no such preview to refresh (a stale
/// comment count until the next natural rebuild costs nothing real).
void showPostCommentsSheet(
  BuildContext context, {
  String? postId,
  String? groupPostId,
  required bool isGroup,
  List<LikeReactor> reactors = const [],
  int reactionCount = 0,
  VoidCallback? onPosted,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CommentsSheetContent(
      postId: postId,
      groupPostId: groupPostId,
      isGroup: isGroup,
      reactors: reactors,
      reactionCount: reactionCount,
      onPosted: onPosted ?? () {},
    ),
  );
}

class PostCommentCard extends StatefulWidget {
  const PostCommentCard({
    super.key,
    this.postId,
    this.groupPostId,
    this.isGroup = false,
    this.reactors = const [],
    this.reactionCount = 0,
  }) : assert(
         postId != null || groupPostId != null,
         'need exactly one of postId/groupPostId',
       );

  final String? postId;
  final String? groupPostId;

  /// Solo (#18181a, margin 10/8/0/8, no border) vs group (#101012, margin
  /// 12/12/0/12, 1px rgba(255,255,255,.07) border) surfaces per the current
  /// Feed.dc.html — the two comment cards share every other pixel value
  /// (toggle header, composer, etc.) but NOT this container styling.
  final bool isGroup;

  /// Backs the mini RealMoji rail shown above the comment list once
  /// expanded — the same reactor data the on-photo reactions strip uses
  /// (PostReactionsStrip), passed through by the caller. Empty hides the
  /// rail (matches the design's own "only if reactions>0" implication).
  final List<LikeReactor> reactors;
  final int reactionCount;

  @override
  State<PostCommentCard> createState() => _PostCommentCardState();
}

class _PostCommentCardState extends State<PostCommentCard> {
  final _ctrl = TextEditingController();
  List<Comment> _comments = const [];
  int _count = 0;
  bool _loading = true;
  bool _sending = false;

  /// Who I am, and whether this post is mine — together these decide which
  /// comments offer Remove. The post-ownership half comes from the server
  /// (i_own_post) rather than being threaded down from every call site,
  /// and returns only a boolean, so asking it on an anonymous post reveals
  /// no author identity.
  String? _myUserId;
  bool _iOwnPost = false;

  bool _canRemove(Comment c) => _iOwnPost || c.userId == _myUserId;

  /// Per-card local flag, not a global one — matches the design doc's own
  /// note ("in the prototype this is a single shared flag across the feed;
  /// in production, scope it per composer/session as appropriate").
  bool _isAnon = false;

  /// Last loaded comments + count per post, kept across rebuilds. The feed
  /// disposes cards that scroll away; rebuilt on the way back UP, a card
  /// used to start empty and GROW once its comment preview landed — above
  /// the viewport, that growth shoves the whole feed ("the feed is
  /// glitching sometimes"). A revisited card now starts at its real size
  /// and refreshes quietly.
  static final Map<String, ({List<Comment> comments, int count})> _cache = {};

  String get _cacheKey => widget.postId ?? 'g:${widget.groupPostId}';

  @override
  void initState() {
    super.initState();
    final cached = _cache[_cacheKey];
    if (cached != null) {
      _comments = cached.comments;
      _count = cached.count;
      _loading = false;
    }
    _load();
    // Placeholder reads centered when empty, but typed text should behave
    // like a normal left-growing input, not stay centered as you type —
    // switch alignment the moment there's real content.
    _ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      // 20, not the old 3 — that capped the EXPANDED list (which per spec
      // scrolls up to a real 200px-tall list) to the same 3 comments the
      // collapsed preview already showed, so expanding never revealed more
      // even when a post had far more real comments.
      CommentService.instance.fetchRecent(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
        limit: 20,
      ),
      CommentService.instance.fetchCount(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
      ),
      CommentService.instance.iOwnPost(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
      ),
      CurrentUserService.instance.resolveId().catchError((_) => ''),
    ]);
    if (!mounted) return;
    var comments = results[0] as List<Comment>;
    var count = results[1] as int;
    if (comments.isEmpty && _isLocalDemoPostId(widget.postId)) {
      comments = _demoFallbackComments();
      count = comments.length;
    }
    _cache[_cacheKey] = (comments: comments, count: count);
    setState(() {
      _comments = comments;
      _count = count;
      _iOwnPost = results[2] as bool;
      _myUserId = (results[3] as String).isEmpty ? null : results[3] as String;
      _loading = false;
    });
  }

  /// A demo/seed post (see [_isLocalDemoPostId]) is never a real Supabase
  /// row — `CommentService.post` would always throw "invalid input syntax
  /// for type uuid" against it, which the catch below turned into a
  /// misleading "Couldn't post your comment." on content that was never
  /// postable in the first place. Guarded here AND the composer disables
  /// itself below (build()) — this check stays as a second line of defense
  /// in case `_send` is ever reached another way (e.g. onSubmitted racing a
  /// disabled-state rebuild).
  bool get _isDemoPost => _isLocalDemoPostId(widget.postId);

  Future<void> _send() async {
    if (_isDemoPost) {
      showGlassToast(
        context,
        "This is demo content — comments here aren't saved.",
      );
      return;
    }
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    // Same lenient pre-post check the composer runs — see
    // ContentModerationService's own doc.
    final moderation = ContentModerationService.instance.check(body);
    if (moderation.blocked) {
      showGlassToast(context, moderation.reason!, isError: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await CommentService.instance.post(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
        body: body,
        anonymous: _isAnon,
      );
      _ctrl.clear();
      await _load();
    } catch (e, st) {
      debugPrint('[PostCommentCard._send] failed: $e\n$st');
      if (mounted) {
        showGlassToast(context, "Couldn't post your comment.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openCommentsSheet() => showPostCommentsSheet(
    context,
    postId: widget.postId,
    groupPostId: widget.groupPostId,
    isGroup: widget.isGroup,
    reactors: widget.reactors,
    reactionCount: widget.reactionCount,
    onPosted: _load,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: widget.isGroup
          ? const EdgeInsets.fromLTRB(12, 12, 12, 0)
          : const EdgeInsets.fromLTRB(8, 10, 8, 0),
      // Explicit report ("there is a black strip over which the typing
      // goes on — i just want the oval enclosure, that's it"): this card's
      // own dark surface sat behind the composer as a second, wider slab,
      // so the input read as a pill floating on a strip rather than as one
      // control. The card is transparent now — the composer's own oval
      // outline (below) is the only enclosure left, and the preview lines
      // sit directly on the feed background.
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: widget.isGroup
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle row now OPENS the full comment view as a bottom sheet
          // (matches the Anonymous feed's own _AnonCommentsSheet pattern —
          // explicit request, replacing the earlier inline expand/collapse
          // which pushed the rest of the card's content down in place).
          // Always rendered — the literal Feed.dc.html source has no
          // separate zero-comment title state at all
          // (commentsToggleLabel is always "View all N comments"); the
          // earlier "Comments"-only fallback here was invented, not in the
          // actual design, and is removed.
          GestureDetector(
            onTap: _openCommentsSheet,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: widget.isGroup
                  ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
                  : const EdgeInsets.fromLTRB(14, 9, 14, 6),
              child: Row(
                children: [
                  CustomPaint(
                    size: const Size(15, 15),
                    painter: _ChatBubbleGlyphPainter(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      // "View all 0 comments" reads as broken — explicit
                      // report. With none yet, the row invites the first
                      // one instead of counting nothing.
                      _count == 0
                          ? 'Be the first to comment'
                          : 'View all $_count comment${_count == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(12, 12),
                    painter: _ChevronDownGlyphPainter(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Always-visible top-2-comment single-truncated-line preview/teaser
          // for the sheet above. Left inset matches the toggle row's icon
          // (15) + gap (7) above it, so comment text lines up under "View
          // all N comments" rather than under the chat-bubble icon — and a
          // real top gap (was 0) so the preview reads as its own block
          // instead of sitting flush against the toggle row.
          if (!_loading && _comments.isNotEmpty)
            Padding(
              padding: widget.isGroup
                  ? const EdgeInsets.fromLTRB(38, 8, 16, 4)
                  : const EdgeInsets.fromLTRB(36, 8, 14, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _comments.length.clamp(0, 2); i++) ...[
                    if (i > 0) const SizedBox(height: 5),
                    // Long-press reaches the same Remove the full sheet
                    // offers, so a comment can be taken down without
                    // opening the thread first. No "..." here — these are
                    // one-line teasers and a trailing glyph would eat the
                    // width the text needs.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: !_canRemove(_comments[i])
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              showCommentActionsMenu(
                                context,
                                commentId: _comments[i].id,
                                isMine: _comments[i].userId == _myUserId,
                                canRemove: true,
                                isAnonymous: _comments[i].isAnonymous,
                                authorUsersId: _comments[i].isAnonymous
                                    ? null
                                    : _comments[i].userId,
                                onDeleted: _load,
                              );
                            },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Explicit report — the preview teaser had text only,
                          // no commenter DP. Small (18px, vs _CommentLine's
                          // 27px in the full sheet) since this is a one-line
                          // truncated preview, not the expanded list.
                          Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF2A2A32),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _avatarPhoto(
                              _comments[i].displayAvatarUrl,
                              name: _comments[i].displayName,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${_comments[i].displayName} ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  TextSpan(
                                    text: _comments[i].body,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // §A5 Composer — restyled per the "Social Post Comment Screen"
          // design handoff (comment-bar-v5): 52px warm-charcoal pill
          // (oklch(27% .015 45) → #2D2420), 1px hairline border at 14%
          // white, 32px identity avatar ringed in cyan (was a 27px avatar
          // with a monochrome swap badge — the design drops the badge and
          // signals "tap to switch identity" with the ring itself), and a
          // 40px circular cyan-gradient send button with a dark paper-plane
          // glyph, replacing the old flat white-alpha send dot.
          Padding(
            // Top inset bumped 14 -> 22: "bring add comment little more
            // down" — more breathing room below the reactions/photo above it.
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
            child: Container(
              height: 52,
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2420),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFF8F5EE).withValues(alpha: 0.14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF040201).withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isAnon = !_isAnon);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      padding: const EdgeInsets.all(2),
                      // The ring carries the identity you're about to
                      // comment under: cyan as yourself, amber as your anon
                      // persona. The design's ring is a fixed cyan, but this
                      // composer has a state the design's doesn't, and the
                      // swapped avatar alone is easy to miss on a 28px
                      // circle — the ring makes the mode readable at a
                      // glance, and the placeholder says it in words.
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isAnon
                            ? const Color(0xFFD8A24A)
                            : const Color(0xFF1AD1D1),
                      ),
                      child: _MyCommentAvatar(isAnon: _isAnon, size: 28),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      enabled: !_isDemoPost,
                      textAlign: TextAlign.left,
                      textAlignVertical: TextAlignVertical.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white,
                        height: 1,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        // Explicit: isCollapsed does NOT clear the theme's
                        // 16px contentPadding, which pushed the text above
                        // the avatar's centre line and left a gap after it.
                        contentPadding: EdgeInsets.zero,
                        // See the community search field's matching
                        // fix (community_join_sheet.dart) — the
                        // global InputDecorationTheme's focusedBorder
                        // overrides a bare `border: InputBorder.none`
                        // the instant this field is focused.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: _isDemoPost
                            ? "Demo post — can't comment here"
                            : (_isAnon
                                  ? 'Comment anonymously…'
                                  : 'Add a comment…'),
                        hintStyle: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFFC8C4B9),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isDemoPost ? null : _send,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _isDemoPost
                            ? null
                            : const LinearGradient(
                                begin: Alignment(-0.6, -1),
                                end: Alignment(0.6, 1),
                                colors: [Color(0xFF36DEDE), Color(0xFF00B2B3)],
                              ),
                        color: _isDemoPost
                            ? Colors.white.withValues(alpha: 0.06)
                            : null,
                        boxShadow: _isDemoPost
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1AD1D1,
                                  ).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      alignment: Alignment.center,
                      child: _sending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF000F0F),
                              ),
                            )
                          : CustomPaint(
                              size: const Size(15, 15),
                              painter: _SendPlaneGlyphPainter(
                                color: _isDemoPost
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : const Color(0xFF000F0F),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Comments sheet — the full comment view, opened via showModalBottomSheet
// from PostCommentCard's toggle row. Mirrors the Anonymous feed's own
// _AnonCommentsSheet pattern (anon_feed_v2/anon_feed_screen.dart: slide-up
// sheet, scrim backdrop, grab handle, RealMoji rail, full scrollable list,
// composer pinned at the bottom) rather than the design file's literal
// inline-expand — explicit request to match that page's interaction, not
// Feed.dc.html's own (which has no separate full-view state at all).
// Self-contained (its own CommentService fetch/post), not sharing state with
// the card behind it — onPosted lets the card refresh its own collapsed
// preview/count after a comment is posted from here.
// ---------------------------------------------------------------------------

class _CommentsSheetContent extends StatefulWidget {
  const _CommentsSheetContent({
    this.postId,
    this.groupPostId,
    required this.isGroup,
    required this.reactors,
    required this.reactionCount,
    required this.onPosted,
  });

  final String? postId;
  final String? groupPostId;
  final bool isGroup;
  final List<LikeReactor> reactors;
  final int reactionCount;
  final VoidCallback onPosted;

  @override
  State<_CommentsSheetContent> createState() => _CommentsSheetContentState();
}

class _CommentsSheetContentState extends State<_CommentsSheetContent> {
  /// See _PostCommentCardState's own copies — same rule, resolved again
  /// here because the sheet is a separate State with its own fetch.
  String? _myUserId;
  bool _iOwnPost = false;

  bool _canRemove(Comment c) => _iOwnPost || c.userId == _myUserId;

  final _ctrl = TextEditingController();
  List<Comment> _comments = const [];
  int _count = 0;
  bool _loading = true;
  bool _sending = false;
  bool _isAnon = false;

  @override
  void initState() {
    super.initState();
    _load();
    _ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      CommentService.instance.fetchRecent(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
        limit: 100,
      ),
      CommentService.instance.fetchCount(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
      ),
      CommentService.instance.iOwnPost(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
      ),
      CurrentUserService.instance.resolveId().catchError((_) => ''),
    ]);
    if (!mounted) return;
    var comments = results[0] as List<Comment>;
    var count = results[1] as int;
    if (comments.isEmpty && _isLocalDemoPostId(widget.postId)) {
      comments = _demoFallbackComments();
      count = comments.length;
    }
    setState(() {
      _comments = comments;
      _count = count;
      _iOwnPost = results[2] as bool;
      _myUserId = (results[3] as String).isEmpty ? null : results[3] as String;
      _loading = false;
    });
  }

  /// See _PostCommentCardState._isDemoPost's own doc — same guard, same
  /// reason, duplicated because this sheet is a separate State class with
  /// its own composer rather than reusing the card's.
  bool get _isDemoPost => _isLocalDemoPostId(widget.postId);

  Future<void> _send() async {
    if (_isDemoPost) {
      showGlassToast(
        context,
        "This is demo content — comments here aren't saved.",
      );
      return;
    }
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    // Same lenient pre-post check the composer runs — see
    // ContentModerationService's own doc.
    final moderation = ContentModerationService.instance.check(body);
    if (moderation.blocked) {
      showGlassToast(context, moderation.reason!, isError: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await CommentService.instance.post(
        postId: widget.postId,
        groupPostId: widget.groupPostId,
        body: body,
        anonymous: _isAnon,
      );
      _ctrl.clear();
      await _load();
      widget.onPosted();
    } catch (e, st) {
      debugPrint('[_CommentsSheetContent._send] failed: $e\n$st');
      if (mounted) {
        showGlassToast(context, "Couldn't post your comment.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isGroup
        ? const Color(0xFF101012)
        : const Color(0xFF18181A);
    final screenH = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: screenH * 0.68,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            // Only where the caller hands over WHO reacted — a profile. In
            // the Friends feed reactor identity never reaches this sheet,
            // and the bare "REALMOJIS · N" heading over an empty strip is
            // what made the same sheet look like a different screen there
            // (explicit report, 2026-10-07: "in friends feed opening
            // comment section shall show only comments").
            if (widget.reactionCount > 0 && widget.reactors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                      child: Text(
                        'REALMOJIS · ${widget.reactionCount}',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08 * 9,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    SizedBox(
                      // 42 avatar + 5 gap + the label's LINE BOX, which is
                      // ~13 at 9pt Inter — not the 9 the font size alone
                      // suggests. That arithmetic was off by 4px and
                      // painted an overflow stripe under the strip.
                      height: 42 + 5 + 13,
                      child: ScrollConfiguration(
                        behavior: const _NoScrollbarBehavior(),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (
                              var i = 0;
                              i < widget.reactors.length;
                              i++
                            ) ...[
                              if (i > 0) const SizedBox(width: 9),
                              _MiniReactorTile(reactor: widget.reactors[i]),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                _count == 0 ? 'Comments' : 'Comments · $_count',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      children: [
                        for (var i = 0; i < _comments.length; i++) ...[
                          if (i > 0) const SizedBox(height: 14),
                          _CommentLine(
                            comment: _comments[i],
                            canRemove: _canRemove(_comments[i]),
                            isMine: _comments[i].userId == _myUserId,
                            onChanged: _load,
                          ),
                        ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2420),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: const Color(0xFFF8F5EE).withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF040201).withValues(alpha: 0.4),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isAnon = !_isAnon);
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          padding: const EdgeInsets.all(2),
                          // Same identity ring as the card composer above.
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isAnon
                                ? const Color(0xFFD8A24A)
                                : const Color(0xFF1AD1D1),
                          ),
                          child: _MyCommentAvatar(isAnon: _isAnon, size: 28),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: false,
                          enabled: !_isDemoPost,
                          textAlign: TextAlign.left,
                          textAlignVertical: TextAlignVertical.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: Colors.white,
                            height: 1,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            // Same fix as the card composer above.
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            hintText: _isDemoPost
                                ? "Demo post — can't comment here"
                                : (_isAnon
                                      ? 'Comment anonymously…'
                                      : 'Add a comment…'),
                            hintStyle: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFFC8C4B9),
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isDemoPost ? null : _send,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _isDemoPost
                                ? null
                                : const LinearGradient(
                                    begin: Alignment(-0.6, -1),
                                    end: Alignment(0.6, 1),
                                    colors: [
                                      Color(0xFF36DEDE),
                                      Color(0xFF00B2B3),
                                    ],
                                  ),
                            color: _isDemoPost
                                ? Colors.white.withValues(alpha: 0.06)
                                : null,
                            boxShadow: _isDemoPost
                                ? null
                                : [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF1AD1D1,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          alignment: Alignment.center,
                          child: _sending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF000F0F),
                                  ),
                                )
                              : CustomPaint(
                                  size: const Size(15, 15),
                                  painter: _SendPlaneGlyphPainter(
                                    color: _isDemoPost
                                        ? Colors.white.withValues(alpha: 0.25)
                                        : const Color(0xFF000F0F),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The comment card's own smaller RealMoji rail (42dp avatars, vs. the
// on-photo strip's 56dp) — same plain-colored-circle style as _ReactorTile.
/// Up to three reactor photos, overlapped left-to-right, each ringed in the
/// card's own dark so they read as a stack rather than a smear.
///
/// Kept to three regardless of how many reacted: the count beside it already
/// carries "how many", and a fourth face only costs width. Anyone who wants
/// the full list expands the section — that's what the chevron is for.
class _ReactorFaceStack extends StatelessWidget {
  const _ReactorFaceStack({required this.reactors});

  final List<LikeReactor> reactors;

  static const double _d = 22;
  static const double _step = 15;

  @override
  Widget build(BuildContext context) {
    final shown = reactors.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: _step * (shown.length - 1) + _d,
      height: _d,
      child: Stack(
        children: [
          // Reversed so the FIRST reactor ends up painted on top — the
          // stack reads left-to-right, newest-first, same order as the
          // expanded row below.
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * _step,
              child: Container(
                width: _d,
                height: _d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF17171A),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1.2,
                  ),
                ),
                child: ClipOval(
                  child: _avatarPhoto(
                    shown[i].displayPhotoUrl,
                    name: shown[i].name,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniReactorTile extends StatelessWidget {
  const _MiniReactorTile({required this.reactor});
  final LikeReactor reactor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProfile(context, reactor.id),
      child: SizedBox(
        width: 42,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The reaction itself, badged on the face — explicit request
            // ("the reaction shall be seen like this in the friends feed,
            // not how it's appearing now"), matching the anon feed's own
            // REACTED strip, where each face carries the emoji it reacted
            // with. Without it the expanded row showed WHO reacted but not
            // WHAT with, which is half the information.
            SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 1.5,
                      ),
                    ),
                    child: ClipOval(
                      // The RealMoji SELFIE, not the reactor's DP — see
                      // LikeReactor.displayPhotoUrl. A RealMoji reaction IS
                      // a face; showing the profile photo with a small
                      // glyph badge instead was reported as "the real emoji
                      // shall be seen here, not their dps".
                      child: _avatarPhoto(
                        reactor.displayPhotoUrl,
                        name: reactor.name,
                      ),
                    ),
                  ),
                  if (reactor.emoji.isNotEmpty)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF17171A),
                        ),
                        child: Text(
                          reactor.emoji,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              reactor.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentLine extends StatelessWidget {
  const _CommentLine({
    required this.comment,
    this.canRemove = false,
    this.isMine = false,
    this.onChanged,
  });

  final Comment comment;

  /// Whether THIS viewer may take this comment down — they wrote it, or
  /// they own the post it sits under. Drives only the affordance; the
  /// server re-checks in delete_comment.
  final bool canRemove;
  final bool isMine;

  /// Called after a successful removal so the list can refetch.
  final VoidCallback? onChanged;

  void _openMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showCommentActionsMenu(
      context,
      commentId: comment.id,
      isMine: isMine,
      canRemove: canRemove,
      isAnonymous: comment.isAnonymous,
      authorUsersId: comment.isAnonymous ? null : comment.userId,
      onDeleted: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _openMenu(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            // Never opens the real profile for an anonymous comment — tap-
            // through would leak exactly the identity is_anonymous exists to
            // hide.
            onTap: comment.isAnonymous
                ? null
                : () => openProfile(context, comment.userId),
            child: Container(
              width: 27,
              height: 27,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2A2A32),
              ),
              clipBehavior: Clip.antiAlias,
              child: _avatarPhoto(
                comment.displayAvatarUrl,
                name: comment.displayName,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: comment.displayName,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text: ' ${comment.body}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                // Feed.dc.html: per-comment timestamp, rgba(255,255,255,.4),
                // 11px, 600, margin-top:2px — was never rendered even though
                // Comment.createdAt already exists on the model.
                const SizedBox(height: 2),
                Text(
                  formatRelativeTime(comment.createdAt),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
          // Visible only to someone who can actually act on it — a "..." that
          // opens Remove is misleading on a comment you may not remove, and
          // long-press alone is undiscoverable.
          if (canRemove)
            GestureDetector(
              onTap: () => _openMenu(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
