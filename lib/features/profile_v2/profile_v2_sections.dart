import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_video.dart';

import '../moderation/post_actions_menu.dart';
import 'album_photo_viewer.dart';
import 'profile_v2_data.dart';
import '../../shared/widgets/avatar_peek.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Backdrop
// ---------------------------------------------------------------------------

/// The gradient header every screen opens with.
///
/// Three stacked layers: the gradient itself, a white highlight wash, and a
/// bottom fade into the page. The fade matters — the identity panel is pulled
/// up over this header, and without the fade its shadow would land on a hard
/// gradient edge.
class PV2Backdrop extends StatelessWidget {
  const PV2Backdrop({
    super.key,
    required this.height,
    required this.gradient,
    required this.washX,
    required this.washY,
    required this.fadeHeight,
    this.bannerUrl,
    this.children = const [],
  });

  final double height;
  final LinearGradient gradient;
  final double washX;
  final double washY;
  final double fadeHeight;

  /// A real cover photo, when one's been uploaded — painted between the
  /// gradient and the wash so the wash/bottomFade keep doing their job
  /// (softening the photo into the page) unchanged. Null (the common case
  /// today) leaves this exactly the flat-gradient backdrop it always was.
  final String? bannerUrl;

  /// Positioned chrome laid over the backdrop (back button, chips, pickers).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
          if (bannerUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
              memCacheWidth: 1080,
                imageUrl: bannerUrl!,
                fit: BoxFit.cover,
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: PV2.wash(x: washX, y: washY),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: fadeHeight,
            child: const DecoratedBox(
              decoration: BoxDecoration(gradient: PV2.bottomFade),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// The circular glass button in the backdrop's top-left (back / settings).
class ChromeButton extends StatelessWidget {
  const ChromeButton({super.key, required this.icon, this.onTap});

  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 20,
      width: 40,
      height: 40,
      fill: const Color(0x6B08080A),
      border: const Color(0x1AFFFFFF),
      onTap: onTap,
      child: Center(child: icon),
    );
  }
}

/// The glass pill in the backdrop's top-right — a ping score on a person
/// profile, a live "N here" count on a group.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.leading,
    required this.label,
    this.fontSize = 16,
  });

  final Widget leading;
  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 20,
      height: 40,
      fill: const Color(0x8008080A),
      border: PV2.accent.withValues(alpha: 0.22),
      padding: const EdgeInsets.only(left: 12, right: 15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 7),
          Text(label, style: PV2.display(size: fontSize)),
        ],
      ),
    );
  }
}

/// The small glass pill that opens the backdrop swatch tray, plus the tray.
class BackdropPicker extends StatelessWidget {
  const BackdropPicker({
    super.key,
    required this.open,
    required this.selected,
    required this.onToggle,
    required this.onPick,
    this.label = 'Backdrop',
  });

  final bool open;
  final int selected;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GlassSurface(
          radius: 17,
          height: 34,
          fill: const Color(0x8008080A),
          border: const Color(0x1FFFFFFF),
          padding: const EdgeInsets.only(left: 10, right: 13),
          onTap: onToggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PV2Icons.image(14, Colors.white),
              const SizedBox(width: 7),
              Text(label, style: PV2.body(size: 11.5, weight: FontWeight.w700)),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(width: 9),
          GlassSurface(
            radius: 21,
            fill: const Color(0x8C08080A),
            border: const Color(0x1AFFFFFF),
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < PV2.backdrops.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onPick(i),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: PV2.backdrops[i],
                        border: Border.all(
                          color: i == selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Identity panel
// ---------------------------------------------------------------------------

/// The rounded panel that overlaps the backdrop.
///
/// The overlap is produced by [BackdropOverlapStack], not by this widget — CSS
/// pulls the panel up with a negative margin, which also lifts everything below
/// it, and Flutter has no negative padding. See that widget for the equivalent.
class IdentityPanel extends StatelessWidget {
  const IdentityPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: PV2.gutter),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: PV2.raised,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: PV2.hairlinePanel),
        boxShadow: PV2.panel,
      ),
      child: child,
    );
  }
}

/// The page scaffold shared by all three Profile v2 screens.
///
/// Handles the three things that separate the 430×932 design canvas from a real
/// phone:
///
/// * **The status bar.** The canvas has none, so its chrome sits at `top: 16`.
///   On device that lands under the clock and notch, so the backdrop is grown
///   by the top inset and the chrome is pushed down by the same amount. Per the
///   design's own rule, backdrop height and panel pull-up are tuned as a pair —
///   growing the height while holding the pull-up keeps the overlap constant.
/// * **Column width.** The canvas is 430 wide; the rule is
///   `width = min(430, screenWidth)` with insets held fixed, so a 402pt phone
///   renders a 402pt column rather than a scaled-down 430.
/// * **Bottom clearance.** The home indicator, plus [extraBottomInset] for any
///   floating chrome the host overlays on top of the page (the app shell's nav
///   pill), so the last row of content is never hidden behind it.
///
/// The overlap itself is CSS `margin-top: -96px`, which lifts the panel *and
/// every sibling after it*. Flutter rejects negative padding, so the backdrop is
/// painted as a Stack layer and the content column starts `height - pullUp` from
/// the top. The spacer is transparent, so chrome underneath stays tappable.
class PV2Page extends StatelessWidget {
  const PV2Page({
    super.key,
    required this.backdropHeight,
    required this.pullUp,
    required this.gradient,
    required this.washX,
    required this.washY,
    required this.fadeHeight,
    required this.chrome,
    required this.children,
    this.extraBottomInset = 0,
    this.allowFullBleed = false,
    this.floatingAction,
    this.onScroll,
    this.onRefresh,
    this.bannerUrl,
  });

  /// Backdrop height at the design's reference size, before the status bar is
  /// added.
  final double backdropHeight;

  final double pullUp;
  final LinearGradient gradient;
  final double washX;
  final double washY;
  final double fadeHeight;

  /// Forwarded straight to PV2Backdrop — see its own doc.
  final String? bannerUrl;

  /// Positioned chrome over the backdrop. Offsets are written as the design
  /// states them; the status bar is compensated for here.
  final List<Widget> chrome;

  final List<Widget> children;

  /// Space reserved below the content for host chrome floating over the page.
  final double extraBottomInset;

  /// Lets a section reach past the PV2.columnWidth column to the real screen
  /// edges (the group profile's attached group posts) — the scroll view
  /// stops clipping to the column. Off everywhere else.
  final bool allowFullBleed;

  /// Pinned to the page's bottom-right, outside the scroll view — the creation
  /// FAB on the self profile. Kept in the same 430px column so it lands beside
  /// the content, not the screen edge, on a wide display.
  final Widget? floatingAction;

  /// Fired on any scroll. Screens use it to close an open dropdown, matching
  /// the design's own scroll handler.
  final VoidCallback? onScroll;

  /// Pull-to-refresh. Null leaves the page un-refreshable, which is right
  /// for a page whose content can't change under the viewer; the profiles
  /// pass their own reload so "scroll up to down and the page reloads"
  /// works here the same way it does on the feed, ping and community tabs.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final height = backdropHeight + topInset;
    final bottomInset = media.padding.bottom + extraBottomInset;

    Widget scroller = SingleChildScrollView(
      clipBehavior: allowFullBleed ? Clip.none : Clip.hardEdge,
      // AlwaysScrollable so a short profile can still be overscrolled far
      // enough to trigger the RefreshIndicator below.
      physics: onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: 44 + bottomInset),
      child: Stack(
        children: [
          PV2Backdrop(
            height: height,
            gradient: gradient,
            washX: washX,
            washY: washY,
            fadeHeight: fadeHeight,
            bannerUrl: bannerUrl,
            children: [
              // Nested so every chrome offset in the screens stays exactly as
              // the design writes it, measured from below the status bar
              // rather than from the physical top edge.
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                bottom: 0,
                child: Stack(clipBehavior: Clip.none, children: chrome),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: height - pullUp),
              ...children,
            ],
          ),
        ],
      ),
    );

    if (onRefresh != null) {
      scroller = RefreshIndicator(
        onRefresh: onRefresh!,
        color: PV2.accent,
        backgroundColor: PV2.page,
        // Clears the backdrop's status-bar overlap so the spinner isn't
        // drawn under the notch.
        edgeOffset: topInset,
        child: scroller,
      );
    }

    if (onScroll != null) {
      scroller = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification) onScroll!();
          return false;
        },
        child: scroller,
      );
    }

    return Scaffold(
      backgroundColor: PV2.page,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
          child: Stack(
            children: [
              Positioned.fill(child: scroller),
              if (floatingAction != null)
                Positioned(
                  right: 16,
                  bottom: 24 + bottomInset,
                  child: floatingAction!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A circular avatar wrapped in a partial conic progress ring, with an optional
/// presence dot or edit badge in the corner.
class RingAvatar extends StatelessWidget {
  const RingAvatar({
    super.key,
    required this.fillTurns,
    required this.fill,
    this.size = 62,
    this.badge,
    this.imageUrl,
    this.onTap,
  });

  final double fillTurns;
  final Gradient fill;
  final double size;
  final Widget? badge;

  /// Tapping the photo itself does whatever the badge does.
  ///
  /// Reported as "I am unable to upload the DP": on your own profile the
  /// only way in was a 22px camera badge, and because that badge was
  /// Positioned at right/bottom -3 inside a SizedBox of exactly [size],
  /// the part of it hanging over the edge was not hit-testable at all
  /// (Clip.none stops the PAINT being clipped, not the hit test) — so the
  /// real target was ~19px in the corner of a 62px circle. The badge now
  /// sits fully inside the box, and the whole circle is a target too.
  final VoidCallback? onTap;

  /// `users.profile_photo_url` — when set, the real uploaded DP renders
  /// inside the ring instead of [fill]'s decorative gradient. BUG FIX
  /// (explicit report — "i cannot see the preview of the uploaded photo of
  /// the dp"): this widget never had photo support at all, on EITHER
  /// MyProfileScreen's own header or TheirProfileScreen's — both already
  /// fetched a real avatarUrl and simply had nowhere to put it, so the
  /// header always showed the gradient no matter what was actually
  /// uploaded. [fill] stays required as the fallback for a null/failed url.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The glowing progress ring (ConicRing) and white halo that used to
          // sit around the DP were removed by request — the photo stands on
          // its own. [fillTurns] is kept so callers don't change.
          Positioned.fill(
            // Press-and-hold shows the DP big (Instagram-style peek) — on
            // both your own profile and anyone else's. Tap is unchanged.
            child: AvatarPeek(
              imageUrl: imageUrl,
              child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: fill,
                ),
                child: (imageUrl == null || imageUrl!.isEmpty)
                    ? null
                    : ClipOval(
                        child: CachedNetworkImage(
              memCacheWidth: 1080,
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          width: size,
                          height: size,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
              ),
            ),
            ),
          ),
          // right/bottom 0, not -3: outside the parent's box a child paints
          // (Clip.none) but never receives a tap, which quietly ate a
          // quarter of this badge's target. See [onTap]'s own note.
          if (badge != null) Positioned(right: 0, bottom: 0, child: badge!),
        ],
      ),
    );
  }
}

/// The full-width gradient primary action (Ping / Add people).
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, this.icon, this.onTap});

  final String label;
  final Widget? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            gradient: PV2.accentButton,
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              BoxShadow(
                color: PV2.accentDeep.withValues(alpha: 0.42),
                offset: const Offset(0, 6),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Text(label, style: PV2.body(size: 13.5, weight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circular recessed secondary action beside [AccentButton].
class InsetIconButton extends StatelessWidget {
  const InsetIconButton({super.key, required this.icon, this.onTap});

  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NeuWell(
      width: 42,
      height: 42,
      circle: true,
      shadows: PV2.insetStd,
      border: PV2.hairlinePanel,
      onTap: onTap,
      child: icon,
    );
  }
}

// ---------------------------------------------------------------------------
// Bento tiles
// ---------------------------------------------------------------------------

/// A score tile: big numeral, tracked caps label, optional trailing icon well.
class ScoreTile extends StatelessWidget {
  const ScoreTile({
    super.key,
    required this.value,
    required this.label,
    this.trailing,
  });

  final String value;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: PV2.display(size: 23, height: 1)),
                const SizedBox(height: 6),
                Text(label, style: PV2.caps(size: 9, tracking: 0.11)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// The 34px recessed square that holds a score tile's glyph.
class IconWell extends StatelessWidget {
  const IconWell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeuWell(width: 34, height: 34, radius: 12, child: child);
  }
}

/// The pairwise-streak hero: a conic ring counting toward a 30-day ceiling,
/// wrapped around a recessed well holding the day count.
class StreakHero extends StatelessWidget {
  const StreakHero({
    super.key,
    required this.days,
    required this.turns,
    required this.withName,
  });

  final int days;
  final double turns;
  final String withName;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      radius: 24,
      border: PV2.hairlineBright,
      innerGlow: Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              children: [
                ConicRing(size: 88, fromTurn: 0.5, fillTurns: turns),
                Positioned(
                  left: 7,
                  top: 7,
                  right: 7,
                  bottom: 7,
                  child: NeuWell(
                    circle: true,
                    width: 74,
                    height: 74,
                    shadows: PV2.insetStd,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$days', style: PV2.display(size: 29, height: 1)),
                        const SizedBox(height: 3),
                        Text(
                          'DAYS',
                          style: PV2.caps(
                            size: 8.5,
                            tracking: 0.14,
                            color: PV2.inkSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Text(
            'You & $withName',
            textAlign: TextAlign.center,
            style: PV2.body(size: 12.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'mutual ping streak',
            style: PV2.body(
              size: 10,
              weight: FontWeight.w600,
              color: PV2.inkLabel,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared album
// ---------------------------------------------------------------------------

/// The "Us" mosaic: a dashed add tile followed by photo tiles, each carrying a
/// privacy badge that flips that one photo between "us" and "mutuals".
class AlbumMosaic extends StatelessWidget {
  const AlbumMosaic({
    super.key,
    required this.photos,
    required this.onToggle,
    this.onAdd,
    this.myUserId,
    this.onPhotosChanged,
    this.onPhotoRemoved,
  });

  final List<AlbumPhoto> photos;
  final ValueChanged<int> onToggle;
  final VoidCallback? onAdd;

  /// Current viewer's `users.id` — when set, a photo's privacy badge is
  /// only tappable if `photo.uploaderId == myUserId` (mirrors
  /// us_album_photos_update_own's RLS: the toggle is own-uploads-only).
  /// Null for the mock/design-gallery AlbumMosaic call sites, where every
  /// AlbumPhoto.uploaderId is also null and the badge stays tappable, same
  /// as before this field existed.
  final String? myUserId;

  /// Called after the full-screen viewer removes a photo, so the album can
  /// refetch. Null in the design gallery, where nothing is removable.
  final VoidCallback? onPhotosChanged;

  /// Fired with the removed photo's id the moment a delete succeeds (tile
  /// menu or full-screen viewer), BEFORE [onPhotosChanged]'s refetch — so
  /// the parent can drop the tile instantly instead of it lingering until
  /// the network round trip lands.
  final ValueChanged<String>? onPhotoRemoved;

  @override
  Widget build(BuildContext context) {
    return Mosaic(
      tiles: [
        MosaicTile(span: 1, ratio: 1, child: _addTile()),
        for (var i = 0; i < photos.length; i++)
          MosaicTile(
            span: photos[i].span,
            ratio: photos[i].ratio,
            child: _photoTile(context, photos[i], i),
          ),
      ],
    );
  }

  Widget _addTile() {
    return DashedBox(
      radius: 18,
      color: Colors.white.withValues(alpha: 0.28),
      child: NeuWell(
        radius: 18,
        shadows: PV2.insetDeep,
        onTap: onAdd,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            PV2Icons.camera(21, Colors.white),
            const SizedBox(height: 7),
            Text(
              'add',
              style: PV2.body(
                size: 10,
                weight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoTile(BuildContext context, AlbumPhoto photo, int index) {
    // Either party can LOCK a currently-shared photo back to private — "if
    // either one of the 2 people locks the post, the live post is deleted
    // and it goes private." us_album_photos_lock_partner's RLS admits
    // exactly this one direction (mutual -> private) for the non-uploader;
    // publishing a private photo wider stays uploader-only (unchanged),
    // which is why the non-uploader arm below is also gated on !isPrivate —
    // a private photo's badge stays inert for them, same as before.
    final canToggle = myUserId == null ||
        photo.uploaderId == myUserId ||
        !photo.isPrivate;
    // Opens the full-screen viewer, starting at this tile — previously
    // nothing on the tile itself was tappable except the small privacy
    // badge in the corner (see AlbumMosaic's own doc). Only real photos
    // (imageUrl set) have anything to view full-screen; mock/design-
    // gallery tiles (a flat color swatch, no real image) stay inert.
    final realPhotos = photos
        .where((p) => p.imageUrl != null || p.videoUrl != null)
        .toList();
    final realIndex = realPhotos.indexOf(photo);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(color: photo.color, boxShadow: PV2.photo),
        child: Stack(
          children: [
            // A Duo VIDEO plays in its tile (2026-10-06).
            if (photo.videoUrl != null)
              Positioned.fill(
                child: AppVideo(
                  url: photo.videoUrl,
                  durationMs: photo.videoMs,
                  fit: BoxFit.cover,
                ),
              )
            else if (photo.imageUrl != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  memCacheWidth: 1080,
                  imageUrl: photo.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: PV2.tileScrim),
              ),
            ),
            // The tap layer has to sit ABOVE the scrim, not under it: a
            // Stack hit-tests children back-to-front, so while this lived
            // below the full-bleed scrim the scrim consumed every touch and
            // the tile was silently inert. The corner badges are added after
            // this, so they still win their own taps.
            if (photo.imageUrl != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showAlbumPhotoViewer(
                    context,
                    photos: realPhotos,
                    initialIndex: realIndex,
                    // A removal in the viewer has to reach the album behind
                    // it, or the mosaic keeps drawing a tile whose row is
                    // already deleted.
                    onChanged: onPhotosChanged,
                    onRemoved: onPhotoRemoved,
                  ),
                ),
              ),
            Positioned(
              top: 7,
              right: 7,
              child: PrivacyBadge(
                isPrivate: photo.isPrivate,
                onTap: canToggle ? () => onToggle(index) : null,
              ),
            ),
            // Three-dot menu, directly on the tile — explicit follow-up:
            // removing a photo used to require opening the full-screen
            // viewer first (the only place the "..." menu lived). Same
            // menu, same showAlbumPhotoActionsMenu call the viewer's own
            // _openMenu makes, so "either party can remove" and the
            // Report/Block behaviour stay identical between the two entry
            // points. Real photos only — a mock/design-gallery tile has no
            // photo.id to act on.
            if (photo.id != null)
              Positioned(
                top: 7,
                left: 7,
                child: GestureDetector(
                  onTap: () => showAlbumPhotoActionsMenu(
                    context,
                    photoId: photo.id!,
                    isMine: photo.uploaderId != null && photo.uploaderId == myUserId,
                    uploaderUsersId: photo.uploaderId,
                    onDeleted: () {
                      onPhotoRemoved?.call(photo.id!);
                      onPhotosChanged?.call();
                    },
                  ),
                  // Same GlassSurface/22px chip language as PrivacyBadge on
                  // the opposite corner, so the two read as a matched pair
                  // rather than two different button styles on one tile.
                  child: GlassSurface(
                    radius: 11,
                    height: 22,
                    width: 26,
                    blur: 10,
                    fill: const Color(0x9904070A),
                    border: Colors.white.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.more_horiz_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: photo.byColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    photo.ago,
                    style: PV2.body(
                      size: 9.5,
                      weight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.92),
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

/// The per-photo privacy control.
///
/// Two cues change at once — the fill inverts *and* the glyph swaps padlock ⇄
/// globe — so the state is readable at tile size without reading the label.
class PrivacyBadge extends StatelessWidget {
  const PrivacyBadge({super.key, required this.isPrivate, this.onTap});

  final bool isPrivate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isPrivate
        ? const Color(0x9904070A)
        : PV2.accent.withValues(alpha: 0.92);
    final border = isPrivate
        ? Colors.white.withValues(alpha: 0.2)
        : PV2.accent.withValues(alpha: 0.92);

    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        radius: 11,
        height: 22,
        blur: 10,
        fill: bg,
        border: border,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isPrivate
                ? PV2Icons.lock(10, Colors.white)
                : PV2Icons.globe(10, Colors.white),
            const SizedBox(width: 4),
            Text(
              isPrivate ? 'us' : 'mutuals',
              style: PV2.body(size: 9, weight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// The legend under the album header explaining the two badge states.
class PrivacyLegend extends StatelessWidget {
  const PrivacyLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Widget icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          label,
          style: PV2.body(
            size: 10,
            weight: FontWeight.w600,
            color: PV2.inkLabel,
          ),
        ),
      ],
    );

    return Row(
      children: [
        item(
          PV2Icons.lock(11, Colors.white.withValues(alpha: 0.5)),
          'just us two',
        ),
        const SizedBox(width: 14),
        Flexible(
          child: item(
            PV2Icons.globe(11, Colors.white),
            'mutual friends · tap badge to switch',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Content tabs
// ---------------------------------------------------------------------------

/// The 3-column post grid. Uses the same `minmax(0, 1fr)` sizing rule as
/// [Mosaic] so the 4:5 tiles stay square-shouldered.
class PostsGrid extends StatelessWidget {
  const PostsGrid({
    super.key,
    required this.posts,
    this.leadingTile,
    this.tileOverlay,
  });

  final List<PostTile> posts;

  /// Prepended as the grid's first cell — the self profile's "add post"
  /// affordance. Absent on someone else's profile, where you cannot post.
  final Widget? leadingTile;

  /// Per-tile chrome laid over the photo — the self profile's options button
  /// and its menu. Absent elsewhere for the same reason.
  final Widget Function(int index)? tileOverlay;

  @override
  Widget build(BuildContext context) {
    return Mosaic(
      tiles: [
        if (leadingTile != null)
          MosaicTile(span: 1, ratio: 4 / 5, child: leadingTile!),
        for (var i = 0; i < posts.length; i++)
          MosaicTile(span: 1, ratio: 4 / 5, child: _tile(posts[i], i)),
      ],
    );
  }

  Widget _tile(PostTile post, int index) {
    // The overlay is layered OUTSIDE the ClipRRect: its menu is wider than the
    // tile, and clipping would cut the panel in half. The photo and its scrim
    // stay clipped to the rounded corners.
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(color: post.color, boxShadow: PV2.photo),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: PV2.postScrim),
              ),
            ),
            if (post.hasReactions)
              Positioned(
                left: 7,
                bottom: 7,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: kFaceSwatches[0],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.reactions}',
                      style: PV2.body(size: 9.5, weight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (tileOverlay == null) return photo;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: photo),
        tileOverlay!(index),
      ],
    );
  }
}

/// A dashed "add" cell sized to sit in a grid or list beside real content.
class AddTile extends StatelessWidget {
  const AddTile({
    super.key,
    required this.label,
    required this.icon,
    this.radius = 16,
    this.labelSize = 9.5,
    this.gap = 8,
    this.onTap,
  });

  final String label;
  final Widget icon;
  final double radius;
  final double labelSize;
  final double gap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      radius: radius,
      color: PV2.accent.withValues(alpha: 0.32),
      child: NeuWell(
        radius: radius,
        shadows: PV2.insetDeep,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            SizedBox(height: gap),
            Text(
              label,
              style: PV2.body(
                size: labelSize,
                weight: FontWeight.w700,
                color: PV2.accent.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The vertical moments list — thumbnail with a date stamp, then kind / title /
/// meta.
class MomentsList extends StatelessWidget {
  const MomentsList({
    super.key,
    required this.moments,
    this.onTap,
    this.onRemove,
  });

  final List<MomentCard> moments;

  /// "Remove from profile" for the viewer's OWN contributed rows (those
  /// with a [MomentCard.replyId]). Null — e.g. someone else's profile —
  /// shows no remove button at all.
  final ValueChanged<MomentCard>? onRemove;

  /// Fires with the tapped row. Null (the design-gallery default) leaves
  /// the list purely decorative, same as it always was.
  final ValueChanged<MomentCard>? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < moments.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _card(moments[i]),
        ],
      ],
    );
  }

  Widget _card(MomentCard moment) {
    final card = NeuCard(
      shadows: PV2.raisedMd,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            height: 78 * 5 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DecoratedBox(
                decoration: BoxDecoration(color: moment.color),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The Moment's own photo, when it has one. The colour
                    // behind it is now a fallback (and the loading state)
                    // rather than the whole thumbnail.
                    if (moment.previewPhotoUrl != null)
                      Positioned.fill(
                        child: CachedNetworkImage(
                          memCacheWidth: 300,
                          imageUrl: moment.previewPhotoUrl!,
                          fit: BoxFit.cover,
                          // Keep the palette colour showing on both — a
                          // broken-image glyph in a 78px tile reads as a
                          // bug, the colour reads as the Moment.
                          placeholder: (_, _) => const SizedBox.shrink(),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    // Keeps the date legible over a bright photo.
                    if (moment.previewPhotoUrl != null)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.42),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.55],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: GlassSurface(
                        radius: 9,
                        height: 17,
                        blur: 8,
                        fill: const Color(0xA804070A),
                        border: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Center(
                          child: Text(
                            moment.stamp,
                            style: PV2.body(
                              size: 8.5,
                              weight: FontWeight.w800,
                              letterSpacing: 8.5 * 0.05,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  moment.kind.toUpperCase(),
                  style: PV2.caps(
                    size: 9,
                    tracking: 0.12,
                    color: Colors.white,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  moment.title,
                  style: PV2.body(
                    size: 14.5,
                    weight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  moment.meta,
                  style: PV2.body(size: 11.5, color: PV2.inkHandle),
                ),
              ],
            ),
          ),
          if (onRemove != null && moment.replyId != null)
            GestureDetector(
              onTap: () => onRemove!(moment),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
    return onTap == null
        ? card
        : GestureDetector(onTap: () => onTap!(moment), child: card);
  }
}

// ---------------------------------------------------------------------------
// Group glyph
// ---------------------------------------------------------------------------

/// A group's initial on its gradient tile.
class GroupGlyph extends StatelessWidget {
  const GroupGlyph({
    super.key,
    required this.initial,
    required this.gradient,
    this.size = 40,
    this.radius = 14,
    this.fontSize = 16,
    this.badge,
    this.iconUrl,
  });

  final String initial;
  final LinearGradient gradient;
  final double size;
  final double radius;
  final double fontSize;
  final Widget? badge;

  /// The group's DP (`groups.icon_url`). The letter glyph is the fallback
  /// for a group that has never set one — it used to be the ONLY thing this
  /// could draw, so an uploaded group photo never appeared in any list.
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80000000),
                  offset: Offset(0, 4),
                  blurRadius: 12,
                ),
              ],
            ),
            child: (iconUrl == null || iconUrl!.isEmpty)
                ? Text(initial, style: PV2.display(size: fontSize))
                : CachedNetworkImage(
                    imageUrl: iconUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    memCacheWidth: (size * 3).round(),
                    errorWidget: (_, _, _) =>
                        Text(initial, style: PV2.display(size: fontSize)),
                  ),
          ),
          if (badge != null) Positioned(right: -3, top: -3, child: badge!),
        ],
      ),
    );
  }
}

/// A tilted card, used for the scattered dip stack and memory collages.
class Tilted extends StatelessWidget {
  const Tilted({super.key, required this.degrees, required this.child});

  final double degrees;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(angle: degrees * math.pi / 180, child: child);
  }
}
