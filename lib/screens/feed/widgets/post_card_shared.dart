import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants.dart';
import '../../../core/glass.dart';
import '../../../features/ping/ping_prompt_sheet.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../services/reaction_service.dart';
import '../../../services/realmoji_service.dart';
import '../../../shared/score_tier.dart';
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
mixin PostReactions<T extends StatefulWidget> on State<T> {
  ReactionSummary? summary;
  bool loadingSummary = false;
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

  Future<void> loadMyRealmojiReaction(String postId) async {
    try {
      final reaction = await RealmojiService.instance.myReaction(postId);
      if (!mounted) return;
      setState(() => myRealmojiReaction = reaction);
    } catch (e, st) {
      debugPrint('[PostReactions.loadMyRealmojiReaction] postId=$postId failed: $e\n$st');
      // Non-fatal — the badge just shows unreacted, same fail-closed
      // convention loadReactionSummary uses below.
    }
  }

  Future<void> loadReactionSummary(String postId) async {
    setState(() => loadingSummary = true);
    try {
      final result = await ReactionService.instance.fetchSummary(postId);
      if (!mounted) return;
      setState(() {
        summary = result;
        loadingSummary = false;
      });
    } catch (e, st) {
      debugPrint('[PostReactions.loadReactionSummary] fetchSummary($postId) failed: $e\n$st');
      if (!mounted) return;
      setState(() => loadingSummary = false);
      // Reaction load failure isn't fatal to the card — it just shows the
      // bare add-reaction icon with no count, same as the empty state.
    }
  }

  Future<void> onEmojiSelected(String postId, String emoji) async {
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
        await ReactionService.instance.removeEmojiReaction(postId);
      } else {
        await ReactionService.instance.setEmojiReaction(
          postId: postId,
          emoji: emoji,
        );
        // Viewer's own score ticks up live on the header badge (see
        // item #6, main_shell.dart's _AnonScoreBadge) — only on a genuine
        // new reaction, not on removing one.
        ViewerScoreService.instance.add(2);
      }
    } catch (e, st) {
      debugPrint('[PostReactions.onEmojiSelected] postId=$postId emoji=$emoji failed: $e\n$st');
      if (!mounted) return;
      setState(() => summary = previous);
      showGlassToast(context, "Couldn't save your reaction.", isError: true);
    }
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
  Future<void> selectPreset(String postId, ReactionPreset preset) async {
    setState(() => showPresetTray = false);
    HapticFeedback.selectionClick();

    final type = realmojiTypeFromGlyph(preset.emoji);
    setState(() => uploadingFaceReaction = true);
    try {
      await RealmojiService.instance.reactWithSaved(postId: postId, emojiType: type);
      if (mounted) setState(() => myRealmojiReaction = type);
      ViewerScoreService.instance.add(2);
    } catch (e, st) {
      debugPrint('[PostReactions.selectPreset] postId=$postId preset=${preset.id} failed: $e\n$st');
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
    String postId,
    ReactionPresetCategory category,
    RealmojiType type,
  ) async {
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
        feedScope: category.wire,
        emojiType: type,
        selfie: result.selfie,
      );
      if (mounted) setState(() => myRealmojiReaction = type);
      ViewerScoreService.instance.add(2);
    } catch (e, st) {
      debugPrint('[PostReactions.captureRealmojiAndReact] postId=$postId type=$type failed: $e\n$st');
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
  Future<void> openAddPresetFlow(
    String postId, {
    required bool allowFaceReactions,
  }) async {
    setState(() => showPresetTray = false);
    final category = allowFaceReactions
        ? ReactionPresetCategory.everyone
        : ReactionPresetCategory.anonymous;
    final preset = await runAddPresetFlow(context, category);
    if (preset == null || !mounted) return;
    await selectPreset(postId, preset);
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
void openReactionLibrary(BuildContext context, {required bool allowFaceReactions}) {
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFF0F0F0),
          border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 1.5),
        ),
        child: Icon(Icons.add_rounded, size: size * 0.66, color: const Color(0xFF444444)),
      ),
    );
  }
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
  });

  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;
  final VoidCallback onTap;
  final double size;

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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _reacted
              ? AppColors.coral.withValues(alpha: 0.12)
              : const Color(0xFFF0F0F0),
          border: Border.all(
            color: _reacted
                ? AppColors.coral.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Center(child: _content()),
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
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
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
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
        child: Center(child: Text(myEmoji!, style: TextStyle(fontSize: h * 0.5))),
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
    return Icon(
      Icons.add_reaction_rounded,
      size: iconSize,
      color: const Color(0xFF666666),
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
    required this.showTray,
    required this.category,
    required this.onSelect,
    required this.onAddNew,
    required this.onCaptureRealmoji,
    this.size = 26,
    this.width,
    this.height,
    this.style = TrayIconVisualStyle.surface,
  });

  final bool allowFaceReactions;
  final FaceReaction? myFaceReaction;
  final String? myEmoji;
  final bool uploading;

  /// Toggles [showTray] on the caller's state (PostReactions.openReactionTray).
  final VoidCallback onTap;

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
        return Positioned(
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
              ),
            ),
          ),
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
        child: Icon(icon, size: kClusterIconSize, color: color, shadows: shadows),
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
    this.size = 28,
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

    if (style == TrayIconVisualStyle.glyph) {
      return TrayHitTarget(
        width: w,
        height: h,
        onTap: onTap,
        child: CustomPaint(
          size: Size(w, h),
          painter: const StickFigureGlyphPainter(),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFF0F0F0),
          border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 1.5),
        ),
        child: Icon(
          Icons.emoji_people_rounded,
          size: size * 0.56,
          color: const Color(0xFF666666),
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
