import 'package:flutter/material.dart';

import '../../services/feed_service.dart' show FeedItem;
import 'profile_v2_tokens.dart';

/// Sample content for Profile v2, transcribed from the design canvas's
/// `renderVals()`.
///
/// The canvas stands in for user photos with flat colour swatches; those are
/// kept here as [Color]s so the screens match the design exactly before real
/// images are wired in. Each photo-bearing model therefore carries a `color`
/// that a later pass replaces with an image URL.

// ---------------------------------------------------------------------------
// Palettes
// ---------------------------------------------------------------------------

/// Placeholder photo swatches, in canvas order.
const kPhotoSwatches = <Color>[
  Color(0xFF3F4A52),
  Color(0xFF6B6152),
  Color(0xFF2B3B34),
  Color(0xFF55606B),
  Color(0xFF4A4038),
  Color(0xFF3D3A30),
  Color(0xFF33403A),
  Color(0xFF3A4048),
];

/// Placeholder avatar swatches, in canvas order.
const kFaceSwatches = <Color>[
  Color(0xFFB9AD97),
  Color(0xFF9DB29A),
  Color(0xFFA79BBF),
  Color(0xFFD7E2E6),
  Color(0xFFE6DDC9),
  Color(0xFFD3DDD9),
];

/// Group glyph gradients (CSS `linear-gradient(150deg, …)`), in canvas order.
final kGroupGradients = <LinearGradient>[
  PV2.cssLinear(150, const [Color(0xFFFFFFFF), Color(0xFF0891A8)]),
  PV2.cssLinear(150, const [Color(0xFF8FD4E8), Color(0xFF4A7F95)]),
  PV2.cssLinear(150, const [Color(0xFFC9F0F7), Color(0xFF6A9AA8)]),
  PV2.cssLinear(150, const [Color(0xFF7FE8E8), Color(0xFF2D7D8F)]),
];

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Whether a shared-album photo is visible to just the pair or to mutuals.
enum PhotoPrivacy { private, shared }

class AlbumPhoto {
  AlbumPhoto({
    required this.color,
    required this.byColor,
    required this.ago,
    required this.span,
    required this.ratio,
    required this.privacy,
    this.id,
    this.imageUrl,
    this.uploaderId,
    this.videoUrl,
    this.videoMs,
  });

  /// A Duo VIDEO (2026-10-06): when set, the tile plays this instead of
  /// showing [imageUrl].
  final String? videoUrl;
  final int? videoMs;

  final Color color;
  final Color byColor;
  final String ago;

  /// Column span in the 3-wide mosaic.
  final int span;
  final double ratio;

  /// Mutable: tapping the badge flips this one photo, with no confirmation.
  PhotoPrivacy privacy;

  /// Real-data fields — null for every mock/design-gallery AlbumPhoto (the
  /// PV2Data-constructed ones), always set for a photo built from
  /// DuoPhotoRow (see TheirProfileScreen's own real-data wiring). When
  /// [imageUrl] is set, the mosaic tile renders it via CachedNetworkImage
  /// instead of the flat [color] swatch. [uploaderId] gates whether the
  /// privacy-toggle badge is interactive — us_album_photos_update_own's own
  /// RLS already enforces this server-side; this is just the UI matching
  /// that constraint instead of showing a control that would 403.
  final String? id;
  final String? imageUrl;
  final String? uploaderId;

  bool get isPrivate => privacy == PhotoPrivacy.private;

  void toggle() {
    privacy = isPrivate ? PhotoPrivacy.shared : PhotoPrivacy.private;
  }
}

class PersonProfile {
  const PersonProfile({
    required this.name,
    required this.handle,
    required this.campus,
    required this.bio,
    required this.anonScore,
    required this.pingScore,
    required this.pairStreak,
    this.userId,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String name;
  final String handle;
  final String campus;
  final String bio;
  final int anonScore;
  final int pingScore;
  final int pairStreak;

  /// The real `users.id` this profile was fetched for — null only for the
  /// mock/demo PV2Data.person constant (design-gallery use, never a real
  /// signed-in person). Real fetches (ProfileLookupService) always set this;
  /// friend-request state and future Us-album wiring key off it.
  final String? userId;

  /// `users.profile_photo_url` — null for the mock PV2Data.person constant;
  /// set by ProfileLookupService.fetchById for a real profile.
  final String? avatarUrl;

  /// `users.banner_url` — same optional-until-fetched shape as avatarUrl.
  /// Null for the mock PV2Data.person constant; set by
  /// ProfileLookupService.fetchById for a real profile.
  final String? bannerUrl;

  /// Fraction of the streak ring to fill. The ceiling is 30 days — a 30+ day
  /// streak fills the ring completely rather than overflowing.
  double get streakTurns => (pairStreak.clamp(0, 30)) / 30;

  /// This person's COMBINED score — the anon and ping halves added, same as
  /// SelfProfile.combinedScore.
  int get combinedScore => anonScore + pingScore;

  /// Real level for THIS person (their own score, not the viewer's) — same
  /// formula as SelfProfile.tier/anonProgress. Backs RingAvatar's fillTurns
  /// on their profile header, replacing a hardcoded 0.58 that never
  /// represented anything real.
  AnonTier get tier => kAnonTiers.lastWhere(
    (t) => combinedScore >= t.min,
    orElse: () => kAnonTiers.first,
  );

  double get anonProgress {
    final t = tier;
    if (t.next == null) return 1;
    return ((combinedScore - t.min) / (t.next! - t.min)).clamp(0.0, 1.0);
  }
}

class GroupCard {
  const GroupCard({
    required this.name,
    required this.initial,
    required this.members,
    required this.gradient,
  });

  final String name;
  final String initial;
  final int members;
  final LinearGradient gradient;
}

class PostTile {
  const PostTile({required this.color, required this.reactions});

  final Color color;
  final int reactions;

  /// The reaction stamp renders only when a post actually has reactions.
  bool get hasReactions => reactions > 0;
}

class MomentCard {
  const MomentCard({
    required this.color,
    required this.stamp,
    required this.kind,
    required this.title,
    required this.meta,
    this.feedItem,
  });

  final Color color;
  final String stamp;

  /// Free-text row label, shown upper-cased ('moment' / 'contributed' for
  /// the two real sources this profile screen merges — see
  /// FeedService.fetchMomentsFor / fetchContributedMoments — or whatever
  /// the mock rows author).
  final String kind;
  final String title;
  final String meta;

  /// The real post this row was built from — null for the mock rows.
  /// MomentsList.onTap needs this to open LockedRepliesScreen via
  /// MomentEntry.fromFeedItem, the same conversion the everyone feed uses.
  final FeedItem? feedItem;

  /// The caller's own reply id when this row is one of their contributions
  /// — the only rows that offer "Remove from profile".
  String? get replyId => feedItem?.momentReplyId;

  /// The photo attached to the Moment, for the row's thumbnail.
  ///
  /// The thumbnail used to be a flat swatch of [color] and nothing else, so
  /// the Moments tab was a list of coloured rectangles that only revealed
  /// what they were once opened — "it's just showing color for preview
  /// without clicking anything". Null for the mock rows and for a Moment
  /// with no photo, which is what [color] is still the fallback for.
  String? get previewPhotoUrl {
    final url = feedItem?.photoUrl;
    return (url == null || url.isEmpty) ? null : url;
  }
}

class MemberChip {
  const MemberChip({
    required this.name,
    required this.color,
    required this.here,
    this.userId,
    this.avatarUrl,
  });

  final String name;

  /// The member's real profile photo. Null falls back to the initial on a
  /// coloured disc — the group roster used to have no avatars at all, so
  /// every member read as an identical letter tile.
  final String? avatarUrl;

  final Color color;

  /// The "here" dot renders only when the member is currently present.
  final bool here;

  /// The real `users.id` this chip was built from — null only for the
  /// mock/demo PV2Data.members rows, same convention as
  /// PersonProfile.userId. Lets the group profile's member rail open the
  /// tapped member's real profile (via openProfile) instead of just
  /// popping the screen.
  final String? userId;
}

class GroupProfile {
  const GroupProfile({
    required this.name,
    required this.handle,
    required this.initial,
    required this.created,
    required this.bio,
    required this.memberCount,
    required this.memoryCount,
    required this.dipCount,
    required this.hereCount,
    this.iconUrl,
  });

  final String name;
  final String handle;
  final String initial;
  final String created;
  final String bio;
  final int memberCount;
  final int memoryCount;
  final int dipCount;
  final int hereCount;

  /// `groups.icon_url` — the group's DP. Null means it has never been set,
  /// and the header falls back to the generated letter glyph.
  final String? iconUrl;
}

/// A dip: a light, member-only post that expires within a day and is never
/// saved to memories.
class DipCard {
  const DipCard({
    required this.color,
    required this.byColor,
    required this.by,
    required this.left,
    required this.tilt,
    this.photoUrl,
    this.posterAvatarUrl,
    this.postedAgo,
    this.caption,
  });

  /// The optional note typed in the composer's Dip box (`dips.caption`,
  /// added by migration 20260908210000). Null for every dip posted before
  /// the column existed, and for anyone who just sends the photo.
  final String? caption;

  final Color color;
  final Color byColor;
  final String by;

  /// Time remaining before it expires.
  final String left;

  /// Degrees of rotation — dips are deliberately scattered, like dropped
  /// polaroids, to distinguish them from the neatly-gridded memories below.
  final double tilt;

  /// The real photo, when this card is backed by a real `dips` row.
  /// Null on every mock DipCard (see PV2Data.dips) — [color] is the
  /// fallback background in that case.
  final String? photoUrl;

  /// The poster's real avatar photo, for the full-screen detail view.
  /// Null on every mock DipCard, and on a real one whose poster has no
  /// `profile_photo_url` — [byColor] is the fallback in both cases, same
  /// as the card's own bottom-left circle.
  final String? posterAvatarUrl;

  /// "23h ago" — when this Dip was posted, not [left] (time until it
  /// expires). Null on every mock DipCard.
  final String? postedAgo;
}

class MemoryCard {
  const MemoryCard({
    required this.day,
    required this.month,
    required this.weekday,
    required this.time,
    required this.title,
    required this.place,
    required this.attendees,
    this.photoUrls,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
  });

  final String day;
  final String month;
  final String weekday;
  final String time;
  final String title;
  final String place;
  final int attendees;

  /// Real photo URLs for this memory, in display order. Null on the mock/
  /// design-gallery entries, which fall back to the [a]–[d] swatches below.
  /// Replaced the old `layout` field when the collage arrangements were
  /// removed — memories render as a uniform grid now, not four shapes.
  final List<String>? photoUrls;

  final Color a;
  final Color b;
  final Color c;
  final Color d;

  /// The swatches as a list, for the grid's placeholder tiles.
  List<Color> get swatches => [a, b, c, d];

  /// At most three faces are shown; the count carries the rest.
  List<Color> get faces =>
      kFaceSwatches.take(attendees.clamp(0, 3)).toList(growable: false);
}

/// A person's own "Us" album with one other person, as listed on My Profile.
class Duo {
  const Duo({
    required this.name,
    required this.color,
    required this.privateCount,
    required this.sharedCount,
  });

  final String name;
  final Color color;
  final int privateCount;
  final int sharedCount;

  int get total => privateCount + sharedCount;

  /// Photos are synthesised from the counts the way the canvas does: the
  /// shared ones lead, then the private remainder.
  List<AlbumPhoto> get photos {
    const spans = [(2, 2.0), (1, 1.0), (1, 1.0), (1, 1.0), (2, 2.0), (1, 1.0)];
    const agos = ['2d', '5d', '1w', '2w', '3w', '1mo', '2mo'];
    return List.generate(total, (j) {
      final isShared = j < sharedCount;
      final span = spans[j % spans.length];
      return AlbumPhoto(
        color: kPhotoSwatches[j % 5],
        byColor: kFaceSwatches[j % kFaceSwatches.length],
        ago: agos[j % agos.length],
        span: span.$1,
        ratio: span.$2,
        privacy: isShared ? PhotoPrivacy.shared : PhotoPrivacy.private,
      );
    });
  }
}

/// A group as listed on My Profile — a compact row rather than a rail card,
/// because the self view leads with activity ("who dipped, when") instead of
/// membership.
class MyGroupRow {
  const MyGroupRow({
    this.id,
    required this.name,
    required this.initial,
    required this.members,
    required this.memories,
    required this.dips,
    required this.last,
    required this.gradient,
    this.memberAvatarUrls = const [],
    this.memberStreaks = const [],
    this.groupStreak = 0,
    this.iconUrl,
  });

  /// The group's DP (`groups.icon_url`), shown in place of the letter glyph
  /// when it has one.
  final String? iconUrl;

  /// The real `groups.id`, when this row was built from a real fetch —
  /// null for every mock/demo entry (PV2Data.myGroups), which have no
  /// backing row. Tapping a row navigates to real data only when this is
  /// set; a null id opens GroupProfileV2Screen on its mock default instead.
  final String? id;

  final String name;
  final String initial;
  final int members;
  final int memories;
  final int dips;
  final String last;
  final LinearGradient gradient;

  /// Up to 3 real member DPs (GroupService.fetchMemberAvatars) — a null
  /// entry means that member has no photo, and the preview falls back to a
  /// plain swatch for just that one circle rather than the old
  /// all-decorative palette. Empty for every mock row.
  final List<String?> memberAvatarUrls;

  /// BLUE 3 per member, aligned 1:1 with [memberAvatarUrls] — each of those
  /// members' own group-ping reply streak, for the small flame under their
  /// circle on the group row. 0 means no run going (no flame drawn).
  final List<int> memberStreaks;

  /// BLUE 2 — the group's shared all-or-nothing streak, shown on the group
  /// row so you can see it without opening the group.
  final int groupStreak;

  bool get hasLiveDip => dips > 0;

  /// A live dip tints the whole row amber — the row's border, its last-activity
  /// line, and the badge on its glyph.
  Color get borderColor =>
      hasLiveDip ? PV2.amber.withValues(alpha: 0.16) : PV2.hairline;

  Color get lastColor => hasLiveDip ? PV2.amber : PV2.inkStamp;
}

class AnonPost {
  const AnonPost({
    required this.color,
    required this.text,
    required this.ago,
    required this.reactions,
  });

  final Color color;
  final String text;
  final String ago;
  final int reactions;
}

/// A LEVEL of the combined score, and the threshold at which the next one
/// begins.
///
/// This was `kAnonTiers` — a five-rung Ghost/Whisper/Shadow/Phantom/Cipher
/// ladder driven by the anon half alone, and a third, separate tier model
/// on top of ScoreTier (score_tier.dart) and ping_page's own inline
/// thresholds. All three now describe the same seven levels of the same
/// combined score. Thresholds match level_for_score() in Postgres exactly;
/// if they ever disagree, the SQL wins — it is what decay re-levels against.
class AnonTier {
  const AnonTier(this.min, this.name, this.next);

  final int min;
  final String name;
  final int? next;
}

const kAnonTiers = <AnonTier>[
  AnonTier(0, 'Ghost', 100),
  AnonTier(100, 'Rookie', 300),
  AnonTier(300, 'Contender', 700),
  AnonTier(700, 'Elite', 1500),
  AnonTier(1500, 'Ace', 3000),
  AnonTier(3000, 'Dominator', 6000),
  AnonTier(6000, 'Legend', null),
];

class SelfProfile {
  const SelfProfile({
    required this.name,
    required this.handle,
    required this.campus,
    required this.bio,
    required this.anonScore,
    required this.pingScore,
    required this.bestRank,
    required this.bestRankIn,
    required this.communityCount,
    required this.anonName1,
    this.anonName2,
    this.activeAnonSlot = 1,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String name;
  final String handle;
  final String campus;
  final String bio;
  final int anonScore;
  final int pingScore;
  final String bestRank;
  final String bestRankIn;
  final int communityCount;

  /// `users.anon_name` — slot 1. Always set (DB column is NOT NULL).
  final String anonName1;

  /// `users.anon_name_2` — slot 2, optional (product ask: second anon name
  /// is optional). Null until the user sets one, either at onboarding or
  /// later via the profile's anon-identity edit sheet.
  final String? anonName2;

  /// `users.active_anon_slot` — which of the two names is "on" right now.
  /// Toggled by the profile's Shuffle control (see MyProfileScreen).
  final int activeAnonSlot;

  /// Whichever anon name is currently active — every render site
  /// (community_screen.dart, group_member_picker_screen.dart, this
  /// screen's own anon-identity cards) reads this, not anonName1/2
  /// directly, so Shuffle just needs to flip [activeAnonSlot].
  String get anonName =>
      activeAnonSlot == 2 && anonName2 != null ? anonName2! : anonName1;

  /// `users.profile_photo_url` — null on the PV2Data.me mock and until
  /// _loadMe's real fetch resolves, same optional-until-fetched shape
  /// name/bio already have.
  final String? avatarUrl;

  /// `users.banner_url` — same optional-until-fetched shape as avatarUrl.
  final String? bannerUrl;

  /// The ONE score shown everywhere — `users.total_score`, the anon and
  /// ping halves added together. The halves are still fetched separately
  /// because decay applies a different percentage to each, but nothing
  /// displays them apart any more.
  int get combinedScore => anonScore + pingScore;

  AnonTier get tier => kAnonTiers.lastWhere(
    (t) => combinedScore >= t.min,
    orElse: () => kAnonTiers.first,
  );

  /// Progress through the current level, 0–1. The top level reads as full.
  double get anonProgress {
    final t = tier;
    if (t.next == null) return 1;
    return ((combinedScore - t.min) / (t.next! - t.min)).clamp(0.0, 1.0);
  }

  String get anonNextLabel {
    final t = tier;
    if (t.next == null) return 'max level';
    final nextTier = kAnonTiers[kAnonTiers.indexOf(t) + 1];
    return '${t.next! - combinedScore} to ${nextTier.name}';
  }
}

// ---------------------------------------------------------------------------
// Sample content
// ---------------------------------------------------------------------------

class PV2Data {
  PV2Data._();

  static const person = PersonProfile(
    name: 'study_bug',
    handle: '@study_bug',
    campus: 'RVCE',
    bio:
        'third year, mostly in the library. ping me if you want a study buddy.',
    anonScore: 412,
    pingScore: 230,
    pairStreak: 14,
  );

  static const me = SelfProfile(
    name: 'theo_b',
    handle: '@theo_b',
    campus: 'RVCE',
    bio:
        'second year. i take more photos than i post. mostly here for the group.',
    anonScore: 412,
    pingScore: 230,
    bestRank: '#3',
    bestRankIn: 'Design Club',
    communityCount: 5,
    anonName1: 'quiet_moth_04',
  );

  static const group = GroupProfile(
    name: 'CS Study Group',
    handle: '@cs_study',
    initial: 'C',
    created: 'Mar 2026',
    bio: 'notes, past papers, and 2am debugging. no spam.',
    memberCount: 4,
    memoryCount: 38,
    dipCount: 5,
    hereCount: 2,
  );

  /// The shared album on a person's profile. Seven photos plus the add tile
  /// close the 3-column grid flush at nine cells.
  static List<AlbumPhoto> sharedAlbum() => [
    AlbumPhoto(
      color: kPhotoSwatches[0],
      byColor: kFaceSwatches[0],
      ago: '2d',
      span: 2,
      ratio: 2,
      privacy: PhotoPrivacy.private,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[1],
      byColor: kFaceSwatches[1],
      ago: '5d',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.shared,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[2],
      byColor: kFaceSwatches[0],
      ago: '1w',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.private,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[3],
      byColor: kFaceSwatches[2],
      ago: '2w',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.private,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[4],
      byColor: kFaceSwatches[1],
      ago: '3w',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.shared,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[5],
      byColor: kFaceSwatches[0],
      ago: '1mo',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.private,
    ),
    AlbumPhoto(
      color: kPhotoSwatches[6],
      byColor: kFaceSwatches[2],
      ago: '1mo',
      span: 1,
      ratio: 1,
      privacy: PhotoPrivacy.private,
    ),
  ];

  static List<GroupCard> groups = [
    GroupCard(
      name: 'CS Study Group',
      initial: 'C',
      members: 4,
      gradient: kGroupGradients[0],
    ),
    GroupCard(
      name: 'Late Night Mess',
      initial: 'L',
      members: 12,
      gradient: kGroupGradients[1],
    ),
    GroupCard(
      name: 'Design Club',
      initial: 'D',
      members: 27,
      gradient: kGroupGradients[2],
    ),
    GroupCard(
      name: 'Gym Regulars',
      initial: 'G',
      members: 9,
      gradient: kGroupGradients[3],
    ),
  ];

  static const posts = <PostTile>[
    PostTile(color: Color(0xFF3A4048), reactions: 42),
    PostTile(color: Color(0xFF6B6152), reactions: 12),
    PostTile(color: Color(0xFF2B3B34), reactions: 0),
    PostTile(color: Color(0xFF4A4038), reactions: 8),
    PostTile(color: Color(0xFF33403A), reactions: 0),
    PostTile(color: Color(0xFF3D3A30), reactions: 24),
  ];

  static const moments = <MomentCard>[
    MomentCard(
      color: Color(0xFF3A4048),
      stamp: '14 AUG',
      kind: 'memory',
      title: 'one year since the first ping',
      meta: '3 photos',
    ),
    MomentCard(
      color: Color(0xFF6B6152),
      stamp: '02 AUG',
      kind: 'milestone',
      title: 'hit a 14 day ping streak',
      meta: 'longest yet',
    ),
    MomentCard(
      color: Color(0xFF2B3B34),
      stamp: '27 JUL',
      kind: 'memory',
      title: 'exam week survival kit',
      meta: 'with CS Study Group',
    ),
  ];

  static const members = <MemberChip>[
    MemberChip(name: 'study_bug', color: Color(0xFFB9AD97), here: true),
    MemberChip(name: 'alex_xyz', color: Color(0xFF9DB29A), here: true),
    MemberChip(name: 'jordan_23', color: Color(0xFFA79BBF), here: false),
    MemberChip(name: 'coffee_talk', color: Color(0xFFD7E2E6), here: false),
    MemberChip(name: 'sunset', color: Color(0xFFE6DDC9), here: false),
    MemberChip(name: 'niko', color: Color(0xFFD3DDD9), here: false),
  ];

  static const dips = <DipCard>[
    DipCard(
      color: Color(0xFF5A4F42),
      byColor: Color(0xFFB9AD97),
      by: 'alex',
      left: '6h',
      tilt: -1.6,
    ),
    DipCard(
      color: Color(0xFF3F4A52),
      byColor: Color(0xFF9DB29A),
      by: 'jordan',
      left: '11h',
      tilt: 1.4,
    ),
    DipCard(
      color: Color(0xFF4A4038),
      byColor: Color(0xFFA79BBF),
      by: 'niko',
      left: '14h',
      tilt: -1.0,
    ),
    DipCard(
      color: Color(0xFF2B3B34),
      byColor: Color(0xFFD7E2E6),
      by: 'coffee',
      left: '20h',
      tilt: 2.0,
    ),
    DipCard(
      color: Color(0xFF55606B),
      byColor: Color(0xFFE6DDC9),
      by: 'sunset',
      left: '23h',
      tilt: -1.2,
    ),
  ];

  static const memories = <MemoryCard>[
    MemoryCard(
      day: '16',
      month: 'aug',
      weekday: 'Saturday',
      time: '9:40 pm',
      title: 'Terrace night, again',
      place: 'Hostel B terrace',
      attendees: 4,
      a: Color(0xFF3F4A52),
      b: Color(0xFF6B6152),
      c: Color(0xFF2B3B34),
      d: Color(0xFF4A4038),
    ),
    MemoryCard(
      day: '09',
      month: 'aug',
      weekday: 'Saturday',
      time: '1:15 pm',
      title: 'Mess food strike lunch',
      place: 'North mess',
      attendees: 5,
      a: Color(0xFF6B6152),
      b: Color(0xFF4A4038),
      c: Color(0xFF3D3A30),
      d: Color(0xFF55606B),
    ),
    MemoryCard(
      day: '27',
      month: 'jul',
      weekday: 'Sunday',
      time: '6:05 am',
      title: 'Sunrise cycle to Nandi',
      place: 'Nandi Hills',
      attendees: 3,
      a: Color(0xFF2B3B34),
      b: Color(0xFF33403A),
      c: Color(0xFF55606B),
      d: Color(0xFF3F4A52),
    ),
    MemoryCard(
      day: '12',
      month: 'jul',
      weekday: 'Saturday',
      time: '11:30 pm',
      title: 'Exam week survival kit',
      place: 'Central library',
      attendees: 4,
      a: Color(0xFF4A4038),
      b: Color(0xFF3D3A30),
      c: Color(0xFF3F4A52),
      d: Color(0xFF6B6152),
    ),
  ];

  static const duos = <Duo>[
    Duo(
      name: 'study_bug',
      color: Color(0xFFB9AD97),
      privateCount: 5,
      sharedCount: 2,
    ),
    Duo(
      name: 'alex_xyz',
      color: Color(0xFF9DB29A),
      privateCount: 8,
      sharedCount: 0,
    ),
    Duo(
      name: 'jordan_23',
      color: Color(0xFFA79BBF),
      privateCount: 3,
      sharedCount: 3,
    ),
    Duo(
      name: 'coffee_talk',
      color: Color(0xFFD7E2E6),
      privateCount: 2,
      sharedCount: 1,
    ),
  ];

  static int get duoPhotoTotal => duos.fold(0, (n, a) => n + a.total);

  static int get duoSharedTotal => duos.fold(0, (n, a) => n + a.sharedCount);

  static final myGroups = <MyGroupRow>[
    MyGroupRow(
      name: 'Terrace Club',
      initial: 'T',
      members: 4,
      memories: 38,
      dips: 5,
      last: 'alex dipped 6h ago',
      gradient: kGroupGradients[0],
    ),
    MyGroupRow(
      name: 'Nandi Riders',
      initial: 'N',
      members: 3,
      memories: 12,
      dips: 0,
      last: 'last memory 27 Jul',
      gradient: kGroupGradients[1],
    ),
    MyGroupRow(
      name: 'Mess Survivors',
      initial: 'M',
      members: 5,
      memories: 24,
      dips: 2,
      last: 'niko dipped 14h ago',
      gradient: kGroupGradients[3],
    ),
  ];

  static int get myMemoryTotal => myGroups.fold(0, (n, g) => n + g.memories);

  static int get myDipTotal => myGroups.fold(0, (n, g) => n + g.dips);

  static const anonPosts = <AnonPost>[
    AnonPost(
      color: Color(0xFF3F4A52),
      text: 'does anyone else just sit in the library to avoid their room',
      ago: '3d',
      reactions: 28,
    ),
    AnonPost(
      color: Color(0xFF6B6152),
      text: 'the mess coffee is genuinely getting worse every week',
      ago: '1w',
      reactions: 61,
    ),
    AnonPost(
      color: Color(0xFF2B3B34),
      text: 'took a walk at 4am and the campus is unreal that early',
      ago: '2w',
      reactions: 14,
    ),
  ];
}
