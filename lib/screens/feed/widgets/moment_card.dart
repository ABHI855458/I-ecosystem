import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/groups/moments/locked_replies_screen.dart';
import '../../../services/feed_service.dart';

// ---------------------------------------------------------------------------
// Moment palettes — the gradients a poster can pick from in AddMomentScreen,
// stored on the row as `posts.moment_color` (an id, not the colors, so the
// look can be retuned here without a data migration). Client-side is the
// single source of truth; an unknown or null id falls back to the first.
// ---------------------------------------------------------------------------

class MomentPalette {
  const MomentPalette({
    required this.id,
    required this.label,
    required this.colors,
    required this.icon,
  });

  final String id;
  final String label;
  final List<Color> colors;
  final IconData icon;
}

const kMomentPalettes = <MomentPalette>[
  MomentPalette(
    id: 'sunset',
    label: 'Sunset',
    colors: [Color(0xFFFF9A6C), Color(0xFFE1306C)],
    icon: Icons.wb_twilight_rounded,
  ),
  MomentPalette(
    id: 'violet',
    label: 'Violet',
    colors: [Color(0xFF405DE6), Color(0xFF833AB4)],
    icon: Icons.auto_awesome_rounded,
  ),
  MomentPalette(
    id: 'ocean',
    label: 'Ocean',
    colors: [Color(0xFF2193B0), Color(0xFF6DD5ED)],
    icon: Icons.waves_rounded,
  ),
  MomentPalette(
    id: 'forest',
    label: 'Forest',
    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
    icon: Icons.park_rounded,
  ),
  MomentPalette(
    id: 'ember',
    label: 'Ember',
    colors: [Color(0xFFF12711), Color(0xFFF5AF19)],
    icon: Icons.local_fire_department_rounded,
  ),
  MomentPalette(
    id: 'midnight',
    label: 'Midnight',
    colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
    icon: Icons.nightlight_round,
  ),
];

MomentPalette momentPaletteFor(String? id) => kMomentPalettes.firstWhere(
      (p) => p.id == id,
      orElse: () => kMomentPalettes.first,
    );

/// The gradient swatches for a new Moment. Presets rather than a free colour
/// pick: the card draws white text straight onto the gradient, so an
/// arbitrary hue could land unreadable.
///
/// Lives here, next to the palettes and the card that renders them, because
/// BOTH moment entry points draw it — AddMomentScreen (profile ➜ + ➜ Add
/// Moment) and the camera composer's Moments destination.
class MomentPaletteRow extends StatelessWidget {
  const MomentPaletteRow({
    super.key,
    required this.selected,
    required this.onSelect,
    this.swatchSize = 42,
  });

  final MomentPalette selected;
  final ValueChanged<MomentPalette> onSelect;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in kMomentPalettes)
          GestureDetector(
            onTap: () => onSelect(p),
            child: Container(
              width: swatchSize,
              height: swatchSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: p.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(swatchSize * 0.31),
                border: Border.all(
                  color: p.id == selected.id
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.12),
                  width: p.id == selected.id ? 2.2 : 1,
                ),
              ),
              child: p.id == selected.id
                  ? Icon(Icons.check_rounded,
                      size: swatchSize * 0.43, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// A Moment's caption IS the card's headline (where the demo reads "Quad
/// Golden Hour"), and that headline must stay on ONE line at 19px — so the
/// composer caps the input here rather than letting the card ellipsize.
const kMomentCaptionMaxChars = 32;

/// How long a Moment stays open for contributions — drives the "3h left"
/// pill. Matches the app's other 24h windows (see FeedService.anonVisibleWindow).
const kMomentLifetime = Duration(hours: 24);

// ---------------------------------------------------------------------------
// MomentEntry — a Moment as the card needs it. Two sources: [kDemoMoments]
// below (hardcoded placeholders, kept so the card is visually testable with
// contributions/replies that don't exist yet) and [MomentEntry.fromFeedItem]
// (a REAL posted moment, posts.post_type = 'moment' — the path
// AddMomentScreen writes through). The demo entries never touch Supabase;
// they stay only because they carry reply/contribution data the real schema
// has nowhere to store yet (see bucket_service.dart: id, title, expires_at,
// community_id).
// ---------------------------------------------------------------------------

class MomentEntry {
  const MomentEntry({
    required this.id,
    required this.title,
    required this.contributorCount,
    required this.timeLeft,
    required this.gradient,
    required this.icon,
    required this.replies,
    this.authorName,
    this.authorIsAnonymous = false,
    this.authorUserId,
  });

  final String id;
  final String title;
  final int contributorCount;

  /// Who posted this Moment, as the card should say it: their real name for
  /// a normal Moment, their anon persona when [authorIsAnonymous].
  ///
  /// A Moment card used to carry no attribution at all — a gradient, a
  /// headline and a countdown, with nothing saying whose it was. Null only
  /// for the demo entries below, which have no author.
  final String? authorName;

  /// True when the Moment was posted anonymously (composer_screen's
  /// `momentAsAnon`, which writes `visibility = 'anonymous'`). The card
  /// then shows the anon persona and a mask, never the real name — the same
  /// rule every other anonymous surface follows.
  final bool authorIsAnonymous;

  /// `posts.user_id` of the poster, so the "..." menu can tell your own
  /// Moment (Remove) from someone else's (Report / Block). Null when the
  /// row masked it, which is exactly what an anonymous Moment does.
  final String? authorUserId;

  /// Pre-formatted, e.g. "6h left" — a real integration would derive this
  /// from `buckets.expires_at`, same as this app's other "Xh"/"Xm" labels
  /// (see LocalPost.timeLabel).
  final String timeLeft;

  final List<Color> gradient;
  final IconData icon;

  /// Hardcoded stand-in for the real reply/contribution list a Bucket would
  /// have (same "swap for real data later" placeholder pattern as the rest
  /// of this class) — feeds LockedRepliesScreen when this card is tapped.
  /// Empty for a real posted moment: nothing stores contributions yet.
  final List<MomentReply> replies;

  /// A real posted Moment (`posts.post_type = 'moment'`) in card shape. The
  /// caption is the headline — capped at [kMomentCaptionMaxChars] by the
  /// composer so it stays on one line — and the countdown is derived from
  /// created_at + [kMomentLifetime], the same way LocalPost.timeLabel derives
  /// its "Xh"/"Xm".
  /// [replyCount] is the real contribution count from `moment_replies`
  /// (MomentService.replyCounts, batched for the whole screenful). Falls
  /// back to the comment count when the caller hasn't fetched it — a Moment
  /// card renders immediately and the count fills in on the next build
  /// rather than blocking the feed on an extra round trip.
  factory MomentEntry.fromFeedItem(FeedItem item, {int? replyCount}) {
    final palette = momentPaletteFor(item.momentColor);
    // An anonymous row comes back with its user_id masked by posts_feed's
    // CASE (see FeedService) — so a missing author id IS the anonymity
    // signal here, not a data gap to paper over. Never fall back to the
    // real name in that case.
    // Two independent signals, and both matter. anon_name is set by
    // posts_feed on anonymous rows only; the masked user_id is what proves
    // there is no identity attached. Either one alone would misread a row
    // whose author simply hadn't resolved yet.
    final anonName = (item.anonName ?? '').trim();
    final anonymous = anonName.isNotEmpty || item.userId.trim().isEmpty;
    final name = anonymous ? anonName : (item.username ?? '').trim();
    return MomentEntry(
      id: item.postId,
      title: (item.caption ?? '').trim().isEmpty ? 'Moment' : item.caption!.trim(),
      contributorCount: replyCount ?? item.commentCount,
      timeLeft: momentTimeLeft(item.createdAt),
      gradient: palette.colors,
      icon: palette.icon,
      replies: const [],
      authorName: anonymous
          ? (name.isEmpty ? 'anonymous' : name)
          : (name.isEmpty ? null : name),
      authorIsAnonymous: anonymous,
      authorUserId: anonymous || item.userId.trim().isEmpty ? null : item.userId,
    );
  }
}

/// "3h left" / "12m left" / "ended" from a Moment's created_at.
String momentTimeLeft(DateTime? createdAt) {
  if (createdAt == null) return '24h left';
  final remaining = createdAt.add(kMomentLifetime).difference(DateTime.now());
  if (remaining.isNegative) return 'ended';
  if (remaining.inHours >= 1) return '${remaining.inHours}h left';
  if (remaining.inMinutes >= 1) return '${remaining.inMinutes}m left';
  return 'ending';
}

final List<MomentEntry> kDemoMoments = [
  MomentEntry(
    id: 'demo-moment-1',
    title: 'Quad Golden Hour',
    contributorCount: 14,
    timeLeft: '3h left',
    gradient: const [Color(0xFFFF9A6C), Color(0xFFE1306C)],
    icon: Icons.wb_twilight_rounded,
    replies: const [
      MomentReply(name: 'mira.j', emoji: '🔥', photoUrl: 'https://picsum.photos/seed/moment1-reply-0/480/680'),
      MomentReply(name: 'theo_b', emoji: '😍', photoUrl: 'https://picsum.photos/seed/moment1-reply-1/480/680'),
      MomentReply(name: 'devon_r', emoji: '💯', photoUrl: 'https://picsum.photos/seed/moment1-reply-2/480/680'),
      MomentReply(name: 'priya_n', emoji: '🥹', photoUrl: 'https://picsum.photos/seed/moment1-reply-3/480/680'),
      MomentReply(name: 'alex_k', emoji: '😂', photoUrl: 'https://picsum.photos/seed/moment1-reply-4/480/680'),
    ],
  ),
  MomentEntry(
    id: 'demo-moment-2',
    title: 'Gameday Watch Party',
    contributorCount: 41,
    timeLeft: '18h left',
    gradient: const [Color(0xFF405DE6), Color(0xFF833AB4)],
    icon: Icons.sports_football_rounded,
    replies: const [
      MomentReply(name: 'jordan.l', emoji: '🏈', photoUrl: 'https://picsum.photos/seed/moment2-reply-0/480/680'),
      MomentReply(name: 'sam_w', emoji: '🔥', photoUrl: 'https://picsum.photos/seed/moment2-reply-1/480/680'),
      MomentReply(name: 'casey_m', emoji: '😆', photoUrl: 'https://picsum.photos/seed/moment2-reply-2/480/680'),
      MomentReply(name: 'riley_p', emoji: '🎉', photoUrl: 'https://picsum.photos/seed/moment2-reply-3/480/680'),
      MomentReply(name: 'quinn_t', emoji: '💯', photoUrl: 'https://picsum.photos/seed/moment2-reply-4/480/680'),
    ],
  ),
  MomentEntry(
    id: 'demo-moment-3',
    title: 'Finals Week Grind',
    contributorCount: 9,
    timeLeft: '2d left',
    gradient: const [Color(0xFF0F2027), Color(0xFF2C5364)],
    icon: Icons.local_cafe_rounded,
    replies: const [
      MomentReply(name: 'nora_f', emoji: '☕', photoUrl: 'https://picsum.photos/seed/moment3-reply-0/480/680'),
      MomentReply(name: 'liam_c', emoji: '😩', photoUrl: 'https://picsum.photos/seed/moment3-reply-1/480/680'),
      MomentReply(name: 'ava_s', emoji: '📚', photoUrl: 'https://picsum.photos/seed/moment3-reply-2/480/680'),
      MomentReply(name: 'ethan_d', emoji: '🥱', photoUrl: 'https://picsum.photos/seed/moment3-reply-3/480/680'),
      MomentReply(name: 'zoe_h', emoji: '🔥', photoUrl: 'https://picsum.photos/seed/moment3-reply-4/480/680'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// MomentCard — glass-themed, weather-app-widget-style card: soft gradient
// background, frosted blur, a headline title, and a time-remaining pill —
// deliberately distinct from a post card (no photo, no reactions/comments)
// so it reads at a glance as "a Moment, not a post" while scrolling.
// ---------------------------------------------------------------------------

class MomentCard extends StatelessWidget {
  const MomentCard({
    super.key,
    required this.moment,
    this.onTap,
    this.onMenu,
  });

  final MomentEntry moment;
  final VoidCallback? onTap;

  /// The "..." — Remove / Report / Block, same menu every other post kind
  /// gets. Null hides the affordance entirely (the demo Moments, which have
  /// no row behind them to report).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 132,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: moment.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: moment.gradient.last.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Frosted glass sheen over the gradient — the "weather app
              // widget" look: soft blur + a faint white wash, not a flat
              // solid gradient block.
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(moment.icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MOMENT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const Spacer(),
                        _TimeLeftPill(label: moment.timeLeft),
                        if (onMenu != null) ...[
                          const SizedBox(width: 2),
                          _MomentMenuButton(onTap: onMenu!),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Text(
                      moment.title,
                      // The headline is one line by contract — the composer
                      // caps the caption at kMomentCaptionMaxChars so it fits;
                      // ellipsis is only a backstop for older/longer rows.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(
                          moment.contributorCount == 0
                              ? 'be the first to add'
                              : '${moment.contributorCount} contributed',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        if (moment.authorName != null) ...[
                          const Spacer(),
                          _PostedByPill(
                            name: moment.authorName!,
                            anonymous: moment.authorIsAnonymous,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeLeftPill extends StatelessWidget {
  const _TimeLeftPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// "by `<name>`" on the Moment card, with a mask instead of a face when the
/// Moment was posted anonymously.
///
/// Truncates rather than wrapping: it shares a row with the contributor
/// count, and a long name pushing that count off the card is worse than an
/// ellipsis on the name.
class _PostedByPill extends StatelessWidget {
  const _PostedByPill({required this.name, required this.anonymous});

  final String name;
  final bool anonymous;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              anonymous
                  ? Icons.theater_comedy_rounded
                  : Icons.person_rounded,
              size: 11,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "..." on a Moment card. Sized to a 32px tap target rather than the
/// glyph's own bounds — the icon alone is far under the minimum and sits
/// right beside the card's own tap-to-open gesture.
class _MomentMenuButton extends StatelessWidget {
  const _MomentMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
