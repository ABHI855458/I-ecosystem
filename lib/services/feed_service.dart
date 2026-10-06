import 'dart:math' as math;
import '../core/feature_flags.dart';
import 'dart:ui';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_user_service.dart';
import 'group_service.dart';
import 'memory_service.dart';
import 'moment_service.dart';
import 'post_service.dart';
import 'storage_service.dart';
import '../shared/time_ago.dart' show parsePostgresTimestamp;

// ---------------------------------------------------------------------------
// FeedItem — unified feed entry (memory collage or single post)
// ---------------------------------------------------------------------------

class FeedItem {
  const FeedItem({
    required this.postId,
    required this.type,
    this.postType,
    this.momentColor,
    required this.userId,
    this.partnerUserId,
    this.partnerName,
    this.partnerAvatarUrl,
    this.pairStreak,
    this.anonName,
    this.username,
    this.branch,
    this.caption,
    this.photoPath,
    this.photoUrl,
    this.photoColor,
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
    this.layoutId,
    this.photos,
    this.videoUrl,
    this.videoMs,
    this.createdAt,
    this.avatarUrl,
    this.commentCount = 0,
    this.groupId,
    this.groupName,
    this.groupIconUrl,
    this.groupPostLocked = false,
    this.groupIsPublic = false,
    this.communityTag,
    this.secondaryPhotoUrl,
    this.insetOnRight = true,
    this.aspectRatio,
    this.momentReplyId,
    this.groupSharedVia,
  });

  /// Group posts only: whose share put this post in MY feed
  /// (group_post_audience_feed.shared_via) — the group profile opens via
  /// this person, so it shows what THEY shared to me. Null for my own
  /// groups and community-wide rows.
  final String? groupSharedVia;

  /// Set only on a profile's "contributed" row: the caller's OWN
  /// moment_replies.id, so that row can be removed from their profile
  /// (MomentService.hideFromProfile) without touching the Moment. For such
  /// a row [photoUrl] is the reply's photo, and [postId] is the parent
  /// Moment — empty if that Moment has since been removed.
  final String? momentReplyId;

  final String postId;
  final String type; // 'memory' | 'single'

  /// Raw `posts.post_type` carried through from the row. [type] only ever
  /// distinguishes memory-vs-single (it drives the collage layout), so
  /// Moments need their own passthrough or the feed can't tell a Moment from
  /// an ordinary single post — which is exactly why posted Moments were
  /// falling back to DesignSoloCard.
  final String? postType;

  /// Preset gradient id for a Moment (see kMomentPalettes). Null otherwise.
  final String? momentColor;

  bool get isMoment => postType == 'moment';

  final String userId;

  /// The SECOND author of a shared (Duo) post — `posts.partner_user_id`.
  /// Null on every ordinary post. When set, the card shows both people:
  /// fused avatars, both names, and a ping goes to the pair.
  final String? partnerUserId;
  final String? partnerName;
  final String? partnerAvatarUrl;

  /// True for a post that came out of a Duo (`post_type = 'us'`).
  bool get isUsPost => postType == 'us';

  /// The pair's ping streak (days), for the blue-flame overlay on an Us
  /// post — see PV2Icons.blueFlameStreak. Filled in by
  /// [FeedService._attachAuthors] via the us_post_streaks RPC, which is
  /// gated by can_view_post() server-side, so this is null rather than 0
  /// for a post the viewer can't actually see. Null on every non-Us post.
  final int? pairStreak;

  /// The author's ANON PERSONA name, set only on an anonymous row
  /// (posts_feed.anon_name, which the view returns for anonymous posts and
  /// nowhere else). Non-null here means "render this as anonymous" — the
  /// real [userId] is NULL/empty on exactly these rows, by the same view.
  final String? anonName;
  final String? username;
  final String? branch;
  final String? caption;
  final String? photoPath;
  final String? photoUrl;
  final Color? photoColor;
  final String? musicTitle;
  final String? musicArtist;
  final String? musicUrl;
  final String? layoutId;

  /// Multi-photo posts (`posts.photo_urls` / `group_posts.photo_urls`, see
  /// migration 20260831000000) AND, separately, a memory's own photo list —
  /// both land here. Null/empty means single-photo: read [photoUrl]
  /// instead, which still holds the cover photo for every row. Resolve via
  /// resolvePostPhotos() (post_photo_carousel.dart) rather than branching
  /// on this directly.
  final List<String>? photos;

  /// A VIDEO post (2026-10-06): group posts and Duo posts can carry a clip
  /// instead of (or alongside) a still. Null for every photo post, which is
  /// what keeps the existing card rendering untouched.
  final String? videoUrl;
  final int? videoMs;

  final DateTime? createdAt;

  /// The poster's real profile photo, for EveryonePostCard's header row.
  /// Filled in by [FeedService._attachAuthors] rather than by a PostgREST
  /// embed: `friends_feed` returns SETOF posts (no user columns at all), so
  /// a join in the select could never cover every feed. One batched
  /// `users` read per page covers all of them uniformly instead.
  final String? avatarUrl;

  /// Same author fields on a new instance — used by
  /// [FeedService._attachAuthors], which resolves posters in one batch after
  /// the rows are mapped.
  FeedItem withAuthor({
    String? username,
    String? avatarUrl,
    String? branch,
    String? partnerName,
    String? partnerAvatarUrl,
    int? pairStreak,
    // The signed read URL for a Duo photo (see StorageService's TICKET
    // 5 doc) — `image_url` on a post_type='us' row is a bare object path,
    // not directly loadable, so _attachAuthors resolves it here in the same
    // batched pass it already uses for streaks. Null for every other post.
    String? resolvedPhotoUrl,
  }) => FeedItem(
    postId: postId,
    type: type,
    postType: postType,
    momentColor: momentColor,
    userId: userId,
    partnerUserId: partnerUserId,
    partnerName: partnerName ?? this.partnerName,
    partnerAvatarUrl: partnerAvatarUrl ?? this.partnerAvatarUrl,
    pairStreak: pairStreak ?? this.pairStreak,
    anonName: anonName,
    username: username ?? this.username,
    branch: branch ?? this.branch,
    caption: caption,
    photoPath: photoPath,
    photoUrl: resolvedPhotoUrl ?? photoUrl,
    photoColor: photoColor,
    musicTitle: musicTitle,
    musicArtist: musicArtist,
    musicUrl: musicUrl,
    layoutId: layoutId,
    photos: photos,
    videoUrl: videoUrl,
    videoMs: videoMs,
    createdAt: createdAt,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    commentCount: commentCount,
    groupId: groupId,
    groupName: groupName,
    groupIconUrl: groupIconUrl,
    communityTag: communityTag,
    secondaryPhotoUrl: secondaryPhotoUrl,
    insetOnRight: insetOnRight,
    aspectRatio: aspectRatio,
  );

  /// Also not wired yet — this feed has no comments-count query in place,
  /// so EveryonePostCard's comment icon/row always reads 0 until one exists.
  final int commentCount;

  /// The group this post belongs to — set only for GROUP posts, alongside
  /// [groupName]. Drives GroupPostCard's own member/post lookups (see
  /// screens/feed/widgets/group_post_cards/group_post_card.dart).
  final String? groupId;

  /// Set only for GROUP posts (group_posts, not the regular per-user
  /// `posts` table) — the group's display name, e.g. "CS Study Group".
  /// Null for a regular individual post. Drives EveryonePostCard's
  /// "Posted by {groupName} · {username}" attribution line and its small
  /// community tag — individual posts show neither (see item #4: the
  /// on-photo community tag was removed from individual anonymous posts;
  /// group posts are the one place a community indicator still belongs,
  /// since it's structurally relevant to a group in a way it isn't to an
  /// anonymous individual).
  final String? groupName;

  /// The group's own DP (`groups.icon_url`) — explicit follow-up: the group
  /// photo, once set (any member can now set it, see
  /// GroupService.updateGroupInfo), should actually appear on that group's
  /// posts in the feed. Null for a regular individual post, or a group post
  /// whose group has no icon set yet — both fall back to
  /// DesignGroupCard/GroupPostCard's own letter-glyph initial, unchanged.
  final String? groupIconUrl;

  /// A PRIVATE group's post reaching the viewer only because they share
  /// the group's community (group_post_audience_feed.locked, see
  /// 20260926060000_locked_group_posts_in_feed.sql). Rendered as a normal
  /// group card — same layout, everything shown — except every photo after
  /// the first is blurred and opening it says "Be a friend to see it".
  /// Flips to false the moment any member shares the post with the viewer.
  final bool groupPostLocked;

  /// This post's group has `visibility = 'public'`
  /// (group_post_audience_feed.group_is_public,
  /// 20260929090000_group_feed_marks_public_groups.sql) — self-joinable
  /// from the group's own screen, so a non-member viewing it in the feed
  /// gets no "Accept" pill (see DesignGroupCard): that pill's
  /// join_group_from_shared_post is for a PRIVATE group's post that was
  /// specifically shared to you, which is a real invitation; a public
  /// group is already open to anyone in its community regardless of
  /// whether this particular post was "shared".
  final bool groupIsPublic;

  /// The community this post belongs to (e.g. "CSE").
  ///
  /// For a GROUP post this is the group's community, shown as a small
  /// tag/pill beside the group attribution line, and ignored when
  /// [groupName] is null.
  ///
  /// For a PERSONAL post it is `posts.community_id`'s name, populated only
  /// by [fetchProfilePostsForViewer] — TheirProfileScreen names the shared
  /// communities from it so a filtered profile explains itself instead of
  /// looking like a quiet one. Cards that render this as a group pill are
  /// unaffected: they already skip it when [groupName] is null.
  final String? communityTag;

  /// The SECOND, un-flattened layer of a dual photo post
  /// (`posts.photo_url_secondary` / `group_posts.photo_url_secondary`) —
  /// null for every ordinary single-photo post AND for a dual post made
  /// before this existed (those are baked into one JPEG in [photoUrl]
  /// already and render exactly as they always have). When set, the feed
  /// card renders [DualPhotoView] instead of a plain image: [photoUrl] is
  /// the full-bleed background, this is the draggable inset.
  final String? secondaryPhotoUrl;

  /// Which corner the inset started in (`posts.inset_on_right`) — today's
  /// posting flow always sets this true (DualInsetGeometry.onRight's own
  /// long-standing convention), kept per-post rather than hardcoded in
  /// case that default ever changes. Meaningless when [secondaryPhotoUrl]
  /// is null.
  final bool insetOnRight;

  /// This post's own `aspect_ratio` (posts/group_posts), as text — decided
  /// once by whoever POSTED it (PostSizePresetPicker at compose time), never
  /// by whoever is viewing it. Parse with [parseStoredAspectRatio]; null or
  /// unreadable falls back to this app's own default frame there, not to
  /// any shared/viewer setting.
  final String? aspectRatio;

  factory FeedItem.fromLocalPost(LocalPost p) => FeedItem(
    postId: p.id,
    type: 'single',
    // Without these two the just-posted Moment loses its identity on the
    // way into the feed and renders as a plain post.
    postType: p.postType,
    momentColor: p.momentColor,
    userId: p.userId,
    username: p.username,
    branch: p.branch,
    caption: p.caption,
    photoPath: p.photoPath,
    photoUrl: p.photoUrl,
    // Local paths, not URLs, pre-upload — the optimistic local card
    // renders them straight from disk, same as photoPath already does.
    photos: (p.photoUrls == null || p.photoUrls!.isEmpty)
        ? null
        : [if (p.photoPath != null) p.photoPath!, ...p.photoUrls!],
    musicTitle: p.musicTitle,
    musicArtist: p.musicArtist,
    musicUrl: p.musicUrl,
    createdAt: p.createdAt,
    // Local path, pre-upload — same convention photoPath/photos already
    // use for the optimistic card. Real URL replaces it once _saveToSupabase
    // resolves and the second, post-insert emit fires (see PostService.
    // addPost's own doc on the two-emit pattern).
    secondaryPhotoUrl: p.secondaryPhotoPath,
    insetOnRight: p.insetOnRight,
    // Stringified rather than left as the double it already is on
    // LocalPost — aspectRatio is text everywhere else (the column, the
    // parser), and this optimistic card must render at the SAME frame the
    // real row will carry once it lands, or the card would visibly resize
    // out from under the poster the moment the server round trip replaces
    // it.
    aspectRatio: p.aspectRatio.toString(),
  );
}

// ---------------------------------------------------------------------------
// FeedService
// ---------------------------------------------------------------------------

class FeedService {
  FeedService._();
  static final instance = FeedService._();

  final _sb = Supabase.instance.client;

  /// One seed for this app process's whole lifetime — generated on first
  /// use, not on every call. Explicit request: "every time they login,
  /// different combinations of photos shall be shown as such, not the same
  /// every time." The feed used to be a plain `.order('created_at', desc)`
  /// with no randomisation at all, so it read identically on every open.
  ///
  /// A FIXED per-launch seed rather than a fresh random draw on every
  /// fetch is deliberate: pull-to-refresh and paginating further down the
  /// SAME feed should keep reading as one coherent shuffled order, not
  /// re-scramble under the reader mid-scroll. Reopening the app (a new
  /// process, which is what "logs in again" means for how far this app is
  /// ever actually backgrounded) draws a new seed and a new order.
  static final int _sessionShuffleSeed =
      DateTime.now().millisecondsSinceEpoch;

  /// Shuffles [items] in place — one already-fetched PAGE, never the query
  /// itself. `.range()`'s offset/limit still walk the same server-side
  /// `created_at DESC` order underneath, so pagination stays exact (no
  /// duplicate or skipped rows across pages); only the DISPLAY order
  /// within each page differs.
  ///
  /// [offset] folds into the seed so different pages don't all shuffle by
  /// the exact same permutation pattern (a fresh `Random(sameSeed)` walks
  /// Fisher-Yates identically every time it's constructed, so two
  /// same-length pages shuffled with the bare session seed would swap the
  /// same positions in the same way — visibly mechanical, not random). The
  /// same page fetched twice in one launch (e.g. a widget rebuild) still
  /// shuffles identically, which is what keeps a given page's order stable
  /// under a rebuild rather than jittering.
  static void _shufflePage(List<dynamic> items, int offset) {
    items.shuffle(math.Random(_sessionShuffleSeed ^ offset));
  }

  /// How long an anonymous post stays visible in the Anon feed / the
  /// author's own Anon profile tab. Enforced as a QUERY FILTER (see
  /// [anonCutoff] below and its call sites), not a delete or an expires_at
  /// column — rows stay in the DB, they just stop being returned. See
  /// supabase/migrations/2026-08-25_feed_rules.sql for the full rationale
  /// and the supporting index. Explicit request bumped this from 24h to
  /// 48h, matching the Everyone/Friends feed's own new [postVisibleWindow].
  static const anonVisibleWindow = Duration(hours: 48);

  /// The `created_at > X` bound for anon visibility, as a UTC ISO string
  /// Postgrest can compare against. Computed per-call (not cached) so a
  /// long-lived app session doesn't keep using a stale cutoff.
  static String anonCutoff() =>
      DateTime.now().toUtc().subtract(anonVisibleWindow).toIso8601String();

  /// How long an ordinary (non-Moment) post stays visible in
  /// [fetchEveryoneFeed] — explicit request ("feed post make it stay
  /// 48 hrs"). Same query-filter approach as [anonVisibleWindow] — nothing
  /// is deleted, the feed just stops returning it.
  ///
  /// SCOPE: this governs [fetchEveryoneFeed] ONLY, which in the shipping
  /// app is reachable only from main.dart's `_screenshotMode` harness. The
  /// live Friends feed does NOT use this — its lifetime rule lives in the
  /// `friends_feed` RPC, where other people's posts have no age limit at
  /// all (`else true`) and only the viewer's OWN posts and Moments expire
  /// at 24h. A request to change how long friends' posts last has to be
  /// made in that RPC; changing this constant would not affect it.
  static const postVisibleWindow = Duration(hours: 48);

  static String postCutoff() =>
      DateTime.now().toUtc().subtract(postVisibleWindow).toIso8601String();

  /// How long a post stays GONE before it comes back.
  ///
  /// Explicit request: "remove the post cards after 48 hrs in their feed,
  /// again shall resurface after 10 days". So a post's life is in two
  /// stretches — live for its first 48h, dark for the next ~8 days, then
  /// permanently browsable again as an archive. Nothing is deleted at any
  /// point; both halves are query filters, same as every other window here.
  ///
  /// The gap is what makes the return feel like a resurfacing rather than
  /// a feed that simply never forgets.
  static const resurfaceAfter = Duration(days: 10);

  static String resurfaceCutoff() =>
      DateTime.now().toUtc().subtract(resurfaceAfter).toIso8601String();

  /// A Moment's own, shorter window — explicit request ("moment shall stay
  /// for 24 hrs"), distinct from a regular post's 48h.
  static const momentVisibleWindow = Duration(hours: 24);

  /// With Moments hidden (kMomentsEnabled = false) the cutoff sits far in
  /// the future, so every "live Moment" clause in every feed and profile
  /// query matches nothing — Moments disappear everywhere at once.
  static String momentCutoff() => kMomentsEnabled
      ? DateTime.now().toUtc().subtract(momentVisibleWindow).toIso8601String()
      : '9999-01-01T00:00:00Z';

  /// Every post id the CURRENT user has already reacted to — the backing
  /// set for the "once reacted, never show it again" feed rule.
  ///
  /// Spans BOTH reaction systems running in parallel in this app: emoji
  /// reactions (`reactions`, ReactionService) and RealMoji selfie reactions
  /// (`post_realmoji_reactions`, RealmojiService). A reaction in either one
  /// hides the post. Per explicit product decision this keys on reactions
  /// ONLY — merely viewing/scrolling past a post does not hide it — so no
  /// view-tracking table is involved.
  ///
  /// Fails OPEN (returns whatever it managed to fetch, or an empty set) so
  /// a reaction-lookup outage degrades to "you might see a post you already
  /// reacted to" rather than an empty feed. Each source is caught
  /// independently for the same reason: post_realmoji_reactions has known
  /// per-environment schema drift (see the migration's own notes), and a
  /// failure there must not take the emoji-reaction filter down with it.
  Future<Set<String>> reactedPostIds({String? userId}) async {
    final ids = <String>{};
    final uid = userId ?? await _resolveUserIdOrNull();
    if (uid == null) return ids;

    try {
      final rows = await _sb
          .from('reactions')
          .select('post_id')
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 8));
      for (final r in (rows as List)) {
        final id = (r as Map)['post_id'] as String?;
        if (id != null) ids.add(id);
      }
    } catch (_) {
      // Non-fatal — see fail-open note above.
    }

    try {
      final rows = await _sb
          .from('post_realmoji_reactions')
          .select('post_id')
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 8));
      for (final r in (rows as List)) {
        final id = (r as Map)['post_id'] as String?;
        if (id != null) ids.add(id);
      }
    } catch (_) {
      // Non-fatal — see fail-open note above.
    }

    return ids;
  }

  /// Every post id the CURRENT user has already PINGED the author of — the
  /// other half of "once they react or ping the post, that post shall not
  /// be shown in the feed to them again" ([reactedPostIds] is the react
  /// half). Backed by `pings.source_post_id`, written by
  /// `ping_post_author()` — see migration 20260914020000_ping_hides_post_
  /// from_feed.sql. A ping sent to a friend directly (not via a post) has
  /// no `source_post_id` and is correctly absent here by construction.
  ///
  /// Fails open to an empty set, same posture as [reactedPostIds]: a
  /// lookup outage should degrade to "you might see a post you already
  /// pinged" rather than an empty feed.
  Future<Set<String>> pingedPostIds({String? userId}) async {
    final ids = <String>{};
    final uid = userId ?? await _resolveUserIdOrNull();
    if (uid == null) return ids;

    try {
      final rows = await _sb
          .from('pings')
          .select('source_post_id')
          .eq('sender_id', uid)
          .not('source_post_id', 'is', null)
          .timeout(const Duration(seconds: 8));
      for (final r in (rows as List)) {
        final id = (r as Map)['source_post_id'] as String?;
        if (id != null) ids.add(id);
      }
    } catch (_) {
      // Non-fatal — see fail-open note above.
    }

    return ids;
  }

  /// Posts to hide from a feed: everything this viewer has already
  /// reacted to or pinged.
  ///
  /// Explicit rule: "the reacted posts shall never appear to them again".
  /// Engagement is permanent — once you have answered a post it is spent,
  /// and it never comes back, not even through the resurfacing window
  /// below.
  ///
  /// This is what makes resurfacing sane. [resurfaceAfter] brings BACK
  /// everything past its dark window, which on its own would grow into an
  /// ever-expanding archive; excluding what you have engaged with means the
  /// pool shrinks as you use the app instead of piling up. The two rules
  /// only work together.
  Future<Set<String>> _skipPostIds() async {
    final results = await Future.wait([reactedPostIds(), pingedPostIds()]);
    return {...results[0], ...results[1]};
  }

  /// Group-post counterpart to [reactedPostIds]. Separate because group
  /// posts live in their own table (`group_posts`) and are referenced by
  /// `group_post_id`, not `post_id` — an id from one namespace must never
  /// be matched against the other. Only the RealMoji table carries
  /// group_post_id; the emoji `reactions` table is posts-only.
  Future<Set<String>> reactedGroupPostIds({String? userId}) async {
    final ids = <String>{};
    final uid = userId ?? await _resolveUserIdOrNull();
    if (uid == null) return ids;

    try {
      final rows = await _sb
          .from('post_realmoji_reactions')
          .select('group_post_id')
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 8));
      for (final r in (rows as List)) {
        final id = (r as Map)['group_post_id'] as String?;
        if (id != null) ids.add(id);
      }
    } catch (_) {
      // Non-fatal, and expected outright on deployments where
      // post_realmoji_reactions has no group_post_id column yet (known
      // drift — see the migration's own notes).
    }

    return ids;
  }

  /// resolveId() throws when nobody is signed in; every feed path should
  /// degrade to "no personalization" rather than blowing up in that case.
  Future<String?> _resolveUserIdOrNull() async {
    try {
      return await CurrentUserService.instance.resolveId();
    } catch (_) {
      return null;
    }
  }

  /// [excludeReacted] applies the "once reacted, never show it again" rule
  /// (see [reactedPostIds]). Filtered CLIENT-side after the fetch rather
  /// than as a `not.in` on the query: the reacted set is unbounded and
  /// grows forever, and PostgREST puts the whole list in the URL, so a
  /// heavy user would eventually blow the request-line limit. The tradeoff
  /// is that a page can come back partially filtered (fewer than `limit`
  /// items); the callers' own infinite scroll handles that by just fetching
  /// the next page, same as it already does for any short page.
  Future<List<FeedItem>> fetchEveryoneFeed({
    int limit = 60,
    int offset = 0,
    bool excludeReacted = true,
  }) async {
    try {
      // Skips both reacted AND pinged posts — see _skipPostIds's own doc.
      // "excludeReacted" is the existing parameter name every caller
      // already passes; kept as-is rather than renamed, since it's still
      // the one flag that turns BOTH exclusions on or off together.
      final reacted = excludeReacted
          ? await _skipPostIds()
          : const <String>{};
      // Plain `.select()`, not `.select('*, memories(*)')` — that embed
      // fails live with PGRST200 (posts.memory_id has no FK backing it, see
      // fetchUserPosts's own doc), which made this query fail wholesale and
      // its remote page silently empty regardless of any filter below.
      // Mirrors fetchUserPosts's existing memory-post exclusion.
      //
      // visibility: restricts this feed to 'everyone'/'friends' posts only
      // (never 'anonymous' or 'community', which have their own feeds) —
      // A1's friends-only audience is enforced by posts_select's own
      // can_view_post() RLS gate for the 'friends' rows that make it back;
      // a non-friend querying this table simply never gets those rows.
      //
      // deleted_at: NOT redundant with RLS despite posts_select already
      // filtering it — a second permissive policy, close_group_view_posts
      // (live-only, not in this repo's schema.sql/migrations), has no
      // soft-delete guard, and permissive policies are OR'd. Same guard
      // fetchUserPosts already carries; see its own doc for how this was
      // confirmed against the live DB.
      // Two different visibility windows in one query — a Moment expires
      // at momentCutoff (24h), everything else at postCutoff (48h). Framed
      // as `(post_type=moment AND created_at>momentCutoff) OR
      // (post_type=neq.moment AND created_at>postCutoff)` via .or() rather
      // than two separate queries, so pagination (.range) still applies
      // against one combined, correctly-ordered result set.
      final rows = await _sb
          .from('posts')
          .select()
          .inFilter('visibility', ['everyone', 'friends'])
          // Personal posts (post_type='single' — PostService's own default
          // for an ordinary post, see its doc) were removed as a feature —
          // an allow-list of what's left (moment, us) rather than excluding
          // 'single'/'memory' individually, so nothing new slips through.
          .inFilter('post_type', ['moment', 'us'])
          .isFilter('deleted_at', null)
          // Two live stretches per post, not one: inside its own fresh
          // window, OR old enough to have resurfaced (see resurfaceAfter).
          // The dark stretch between them is the whole point — a post that
          // never left would not read as coming back.
          // A Moment never resurfaces: after 24h it's gone for good, so the
          // resurface branch applies to non-Moment posts only.
          .or(
            'and(post_type.eq.moment,created_at.gt.${momentCutoff()}),'
            'and(post_type.neq.moment,created_at.gt.${postCutoff()}),'
            'and(post_type.neq.moment,created_at.lt.${resurfaceCutoff()})',
          )
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 10));

      // BUG FIX ("every time they login, different combinations of photos
      // shall be shown, not the same every time"): shuffles the DISPLAY
      // order of this already-fetched page only — see _shufflePage's own
      // doc for why the underlying .range() query is untouched.
      final rowList = (rows as List).toList();
      _shufflePage(rowList, offset);

      final items = rowList
          .where((r) {
            if (reacted.isEmpty) return true;
            final id = (r as Map)['id'] as String?;
            return id == null || !reacted.contains(id);
          })
          .map<FeedItem>(
            (r) => _postItemFromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      // Posters resolved in one batched read — see _attachAuthors. Without
      // it every card in this feed renders as "someone".
      return _attachAuthors(items);
    } catch (_) {
      return [];
    }
  }

  /// ANONYMOUS Moments for the Friends/Everyone feed.
  ///
  /// A Moment posted anonymously reached no feed at all: the main feed query
  /// filters visibility IN ('everyone','friends'), and the Anon feed renders
  /// ordinary post cards, not Moment cards. So it simply vanished — reported
  /// as "the moment didn't even appear in the feed".
  ///
  /// Read through `posts_feed`, NOT `posts`, and that is the whole point:
  /// the view NULLs user_id on an anonymous row the caller doesn't own and
  /// hands back anon_name instead. Widening the main query's visibility
  /// filter would have been simpler and would have shipped the anon author's
  /// real user id to every friend's device.
  ///
  /// Same 24h window Moments get everywhere else, and — since this pass —
  /// the same reacted/pinged exclusion as every other source in the feed.
  ///
  /// [excludeReacted] was previously absent here, which made anon Moments
  /// the one thing in the Friends feed that came BACK after you engaged
  /// with it: `fetchFriendsFeed` and `fetchFriendsGroupFeed` both subtract
  /// [_skipPostIds], this did not, so a reacted anon Moment reappeared on
  /// the next refresh. Filtered client-side after the read rather than in
  /// the query, matching how the sibling fetches do it (the id set can be
  /// large enough to blow the request line as an `in.()` filter — see
  /// fetchEveryoneFeed's own note).
  Future<List<FeedItem>> fetchAnonMoments({
    int limit = 10,
    bool excludeReacted = true,
  }) async {
    try {
      final reacted = excludeReacted
          ? await _skipPostIds()
          : const <String>{};
      final rows = await _sb
          .from('posts_feed')
          .select()
          .eq('visibility', 'anonymous')
          .eq('post_type', 'moment')
          .gt('created_at', momentCutoff())
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));
      return [
        for (final r in (rows as List))
          if (reacted.isEmpty ||
              !reacted.contains((r as Map)['id'] as String? ?? ''))
            _postItemFromRow(Map<String, dynamic>.from(r as Map)),
      ];
      // Deliberately NOT run through _attachAuthors: there is no author id
      // to resolve on these rows, and asking would be the leak.
    } catch (_) {
      return [];
    }
  }

  /// The real "Friends" feed — posts whose audience admits the viewer:
  /// the author (or Duo partner) put the viewer in their Friends circle, or
  /// in one of the specific circles the post was sent to, or the post names
  /// a community the viewer belongs to. Backed by the `friends_feed` RPC
  /// (SECURITY DEFINER, via post_audience_admits()) rather than a
  /// client-side `.or()` filter — see 20260926000000_circles_replace_
  /// friendships.sql.
  ///
  /// No shuffle, no demo-card padding: this is a real, chronological feed.
  Future<List<FeedItem>> fetchFriendsFeed({
    int limit = 20,
    int offset = 0,
    // BUG FIX / RULING REVERSAL — explicit request: "the friends feed shall
    // have all the posts which shall be visible to user... no posts shall
    // go out of his feed [whether] reacted, unreacted or [at] any time
    // as-is — except [that it's only] his friends['] [posts]". The ONLY
    // filter on this feed is meant to be "can this viewer see it at all"
    // (accepted friend, or shared community/audience — friends_feed's own
    // WHERE clause) — reacted/pinged state must never additionally remove
    // something the viewer is otherwise allowed to see.
    //
    // _skipPostIds' "once reacted, never show it again" rule (still correct
    // and untouched for fetchEveryoneFeed/the anon feed's own resurfacing
    // system) was being applied here too by a shared default, which is what
    // caused this — a friend's post the viewer had already reacted to
    // simply vanished from Friends, even though nothing about visibility
    // had changed.
    bool excludeReacted = false,
  }) async {
    try {
      // Skips both reacted AND pinged posts — see _skipPostIds's own doc.
      // "excludeReacted" is the existing parameter name every caller
      // already passes; kept as-is rather than renamed, since it's still
      // the one flag that turns BOTH exclusions on or off together.
      final reacted = excludeReacted
          ? await _skipPostIds()
          : const <String>{};
      final rows = await _sb
          .rpc(
            'friends_feed',
            params: {'p_limit': limit, 'p_offset': offset},
          )
          .timeout(const Duration(seconds: 10));

      final items = (rows as List)
          .where((r) {
            if (reacted.isEmpty) return true;
            final id = (r as Map)['id'] as String?;
            return id == null || !reacted.contains(id);
          })
          .map<FeedItem>(
            (r) => _postItemFromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      // Posters resolved in one batched read — see _attachAuthors. Without
      // it every card in this feed renders as "someone".
      return _attachAuthors(items);
    } catch (_) {
      return [];
    }
  }

  /// Fills in each item's poster (username, avatar, branch) in ONE batched
  /// `users` read, and returns the items in the same order.
  ///
  /// This exists as a post-pass rather than a PostgREST embed because no
  /// single embed could cover every feed: `friends_feed` is an RPC
  /// returning `SETOF posts` — the rows carry no user columns at all and
  /// there is nothing to join onto. Without this every post in the
  /// Everyone/Friends feeds and on a profile rendered as the literal string
  /// "someone" (everyone_feed_screen.dart's `item.username ?? 'someone'`),
  /// because _postItemFromRow never set the field.
  ///
  /// `username` is preferred over `name`, matching fetchGroupFeed's own
  /// resolution; rows predating the username column fall back to `name`.
  /// Fails soft: on any error the items come back exactly as passed in, so
  /// a lookup problem degrades the header to its glyph instead of emptying
  /// the feed.
  Future<List<FeedItem>> _attachAuthors(List<FeedItem> items) async {
    // Both authors. A shared (Duo) post has a second one, and leaving
    // it out rendered the co-author as a blank half of the fused header.
    final ids = <String>{
      for (final i in items) ...[
        if (i.userId.isNotEmpty) i.userId,
        if ((i.partnerUserId ?? '').isNotEmpty) i.partnerUserId!,
      ],
    }.toList();
    if (ids.isEmpty) return items;
    try {
      // Authors, Duo streaks and Duo photo URLs are independent — fetched
      // together, not one after another (each trip to the database region
      // costs ~150ms+; this was three in a row before the feed could show).
      final usPostIds = [
        for (final i in items)
          if (i.isUsPost) i.postId,
      ];
      final usPhotoPaths = <String>{
        for (final i in items)
          if (i.isUsPost && (i.photoUrl ?? '').isNotEmpty) i.photoUrl!,
      }.toList();
      final usersFuture = _sb
          .from('users')
          .select('id, username, name, profile_photo_url, department')
          .inFilter('id', ids)
          .timeout(const Duration(seconds: 10));
      final streaksFuture = usPostIds.isEmpty
          ? Future<Map<String, int>>.value(const {})
          : _sb
              .rpc('us_post_streaks', params: {'p_post_ids': usPostIds})
              .timeout(const Duration(seconds: 8))
              .then<Map<String, int>>((rows) => {
                    for (final r in (rows as List).cast<Map<String, dynamic>>())
                      r['post_id'] as String: (r['streak'] as num?)?.toInt() ?? 0,
                  })
              .catchError((_) => const <String, int>{});
      final signedFuture = Future.wait(
        usPhotoPaths.map(StorageService.signedDuoPhotoUrl),
      );

      final rows = await usersFuture;
      final byId = <String, Map<String, dynamic>>{
        for (final r in rows)
          (Map<String, dynamic>.from(r as Map))['id'] as String:
              Map<String, dynamic>.from(r as Map),
      };
      String? nameOf(Map<String, dynamic> u) =>
          (u['username'] as String?)?.trim().isNotEmpty == true
              ? (u['username'] as String).trim()
              : (u['name'] as String?)?.trim();

      final streakById = await streaksFuture;
      final signed = await signedFuture;
      final signedUrlByPath = <String, String>{
        for (var j = 0; j < usPhotoPaths.length; j++)
          if (signed[j] != null) usPhotoPaths[j]: signed[j]!,
      };
      String? resolvedUrlFor(FeedItem i) =>
          i.isUsPost ? signedUrlByPath[i.photoUrl] : null;

      return [
        for (final i in items)
          if (byId[i.userId] case final u?)
            i.withAuthor(
              username: nameOf(u),
              avatarUrl: u['profile_photo_url'] as String?,
              branch: u['department'] as String?,
              partnerName: byId[i.partnerUserId] == null
                  ? null
                  : nameOf(byId[i.partnerUserId]!),
              partnerAvatarUrl:
                  byId[i.partnerUserId]?['profile_photo_url'] as String?,
              pairStreak: streakById[i.postId],
              resolvedPhotoUrl: resolvedUrlFor(i),
            )
          // Still resolve the partner even when the primary author didn't
          // come back — otherwise a shared post loses BOTH names to one
          // missing row.
          else if (byId[i.partnerUserId] case final pu?)
            i.withAuthor(
              partnerName: nameOf(pu),
              partnerAvatarUrl: pu['profile_photo_url'] as String?,
              pairStreak: streakById[i.postId],
              resolvedPhotoUrl: resolvedUrlFor(i),
            )
          else if (resolvedUrlFor(i) case final url?)
            i.withAuthor(resolvedPhotoUrl: url)
          else
            i,
      ];
    } catch (_) {
      return items;
    }
  }

  /// Row -> FeedItem for a `posts` row selected as `*, memories(*)`.
  /// Shared by [fetchEveryoneFeed] and [fetchUserPosts] so the profile and
  /// the feed can never drift on how a post is read — a memory row keeps
  /// type == 'memory' (the collage layout depends on it), everything else
  /// comes back as 'single' carrying its raw post_type through.
  FeedItem _postItemFromRow(Map<String, dynamic> m) {
    final memory = m['memories'] as Map<String, dynamic>?;

    if (memory != null) {
      final photos = (memory['photos'] as List?)?.cast<String>();
      final photoUrls = photos
          ?.map((p) => MemoryService.instance.publicUrl(p))
          .toList();
      return FeedItem(
        postId: m['id'] as String? ?? '',
        type: 'memory',
        userId: m['user_id'] as String? ?? '',
        layoutId: memory['layout_id'] as String?,
        photos: photoUrls,
        // posts.created_at (and this posts_feed/memories projection of it)
        // is `timestamp` with NO time zone — PostgREST serializes it with
        // no Z/offset suffix, which bare DateTime.tryParse reads as LOCAL
        // time instead of the UTC it actually is. On a device east of UTC
        // (IST etc.) every post's "age" came out inflated by the zone
        // offset — reported as "the time in anon posts isn't showing
        // correctly". parsePostgresTimestamp is the fix used elsewhere in
        // this app for exactly this column shape; see its own doc.
        createdAt: m['created_at'] != null
            ? parsePostgresTimestamp(m['created_at'] as String)
            : null,
      );
    }

    return FeedItem(
      postId: m['id'] as String? ?? '',
      type: 'single',
      postType: m['post_type'] as String?,
      momentColor: m['moment_color'] as String?,
      userId: m['user_id'] as String? ?? '',
      partnerUserId: m['partner_user_id'] as String?,
      anonName: m['anon_name'] as String?,
      caption: m['content'] as String?,
      photoUrl: m['image_url'] as String?,
      photos: (m['photo_urls'] as List?)?.cast<String>(),
      musicTitle: m['music_title'] as String?,
      musicArtist: m['music_artist'] as String?,
      musicUrl: m['music_url'] as String?,
      // Same fix as the memory branch above — see its own doc.
      createdAt: m['created_at'] != null
          ? parsePostgresTimestamp(m['created_at'] as String)
          : null,
      secondaryPhotoUrl: m['photo_url_secondary'] as String?,
      insetOnRight: m['inset_on_right'] as bool? ?? true,
      // Only profile_posts_for_viewer projects this; every other read
      // leaves it null, which is the existing behaviour for personal posts.
      communityTag: m['community_name'] as String?,
      aspectRatio: m['aspect_ratio'] as String?,
    );
  }

  /// How many posts a user has, without fetching any of them.
  ///
  /// Backs the locked preview on a non-friend's profile: it can say "8
  /// posts" without a single post reaching that device. `head: true` means
  /// PostgREST returns the count and no rows at all.
  ///
  /// Fails soft to 0 — a missing count should read as a quiet profile, not
  /// an error.
  Future<int> countUserPosts(String userId) async {
    try {
      final res = await _sb
          .from('posts')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .neq('post_type', 'memory')
          .timeout(const Duration(seconds: 8));
      return res;
    } catch (_) {
      return 0;
    }
  }

  /// Posts for one user's profile Posts tab — [userId] null means the
  /// caller's own profile. Newest first, same fail-closed-to-empty contract
  /// the feeds use.
  ///
  /// The `visibility` filter is load-bearing, not decoration: posts_select
  /// (schema.sql) lets an author read their OWN anonymous rows, so without
  /// it a person's anonymous posts would surface in their public Posts tab —
  /// which is the one place they must never appear. Anonymous content has
  /// its own owner-only tab; Moments have their own tab too, hence the first
  /// post_type filter.
  ///
  /// The `deleted_at` filter is NOT redundant with RLS, though it looks it.
  /// posts_select does carry `deleted_at IS NULL`, but it is not the only
  /// permissive SELECT policy on `posts` — a second one, close_group_view_
  /// posts (live-only; it is not in this repo's schema.sql or migrations, and
  /// is referenced only in a comment in 20260903000000), has no soft-delete
  /// guard, and permissive policies are OR'd. Verified against the live
  /// database: setting deleted_at on a post left it still readable. Without
  /// this filter a deleted post reappears on the next refetch.
  ///
  /// Memory posts are excluded as well, and NOT for a product reason: a
  /// memory row carries no image_url of its own (MemoryService writes only
  /// user_id/post_type/memory_id — the photos live on the `memories` row),
  /// and the `memories(*)` embed that would fetch them does not work against
  /// the live database. PostgREST rejects it with PGRST200 "Could not find a
  /// relationship between 'posts' and 'memories'" — posts.memory_id has no
  /// FK constraint backing it. Including memories here would render blank
  /// cards, so they stay out until that relationship exists. NOTE this is
  /// the same embed [fetchEveryoneFeed] uses, which means that query is
  /// failing wholesale and its remote page is silently empty — a separate,
  /// pre-existing bug, untouched here.
  Future<List<FeedItem>> fetchUserPosts({
    String? userId,
    int limit = 50,
  }) async {
    try {
      final uid = userId ?? await CurrentUserService.instance.resolveId();
      final rows = await _sb
          .from('posts')
          .select()
          .or('user_id.eq.$uid,partner_user_id.eq.$uid')
          .inFilter('visibility', ['everyone', 'friends'])
          // Personal (post_type IS NULL) posts were removed as a feature —
          // this tab now shows only Duo posts. Moments have their own
          // tab (fetchMomentsFor); memories are excluded for the pre-existing
          // reason below.
          .eq('post_type', 'us')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      final items = (rows as List)
          .map<FeedItem>(
            (r) => _postItemFromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      // Posters resolved in one batched read — see _attachAuthors. Without
      // it every card in this feed renders as "someone".
      return _attachAuthors(items);
    } catch (_) {
      return [];
    }
  }

  /// Where the caller stands relative to [userId], as the server sees it:
  /// `self`, `friend`, `community`, or `locked`.
  ///
  /// This is the ONLY thing the profile screen should branch on for
  /// visibility. Resolving it client-side from a friendship row would miss
  /// the community case entirely, and would put the rule in two places
  /// that can drift.
  ///
  /// Fails closed to `locked` — an unreadable answer must never open a
  /// profile up.
  Future<String> profileAccessState(String userId) async {
    try {
      final res = await _sb
          .rpc('profile_access_state', params: {'p_profile': userId})
          .timeout(const Duration(seconds: 8));
      final s = res as String?;
      return (s == null || s.isEmpty) ? 'locked' : s;
    } catch (_) {
      return 'locked';
    }
  }

  /// Someone else's profile posts, already filtered by the server to what
  /// this viewer is allowed to see (profile_posts_for_viewer).
  ///
  /// Deliberately NOT fetchUserPosts + a client-side narrowing: a viewer's
  /// device must never receive posts it may not see, which is the same rule
  /// TheirProfileScreen._loadGated already follows. A `locked` viewer gets
  /// zero rows from the RPC itself, and a `community` viewer gets only the
  /// shared-community slice — neither ever has the rest on the device.
  Future<List<FeedItem>> fetchProfilePostsForViewer(String userId) async {
    try {
      final rows = await _sb
          .rpc('profile_posts_for_viewer', params: {'p_profile': userId})
          .timeout(const Duration(seconds: 10));
      final items = (rows as List)
          .map<FeedItem>(
            (r) => _postItemFromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      return _attachAuthors(items);
    } catch (_) {
      return [];
    }
  }

  /// A user's own Moments, newest first — backs the profile's Moments tab,
  /// which was rendering hardcoded PV2Data.moments until now. [userId]
  /// null means the caller's own (the common case); passing another
  /// user's id is what lets TheirProfileScreen show real Moments instead
  /// of the same mock rows for everyone. Filtered server-side on post_type
  /// so it stays a cheap indexed read (see posts_post_type_idx) — Moments
  /// are always visibility='everyone' (see composer_screen.dart's _send),
  /// so this reads under the same RLS fetchUserPosts already relies on for
  /// someone else's posts. Fails closed to an empty list, same as the
  /// feeds.
  Future<List<FeedItem>> fetchMomentsFor({
    String? userId,
    int limit = 50,
  }) async {
    try {
      final uid = userId ?? await CurrentUserService.instance.resolveId();
      final rows = await _sb
          .from('posts')
          .select()
          .eq('user_id', uid)
          .eq('post_type', 'moment')
          // Anonymous Moments belong to the profile's ANON tab, not this
          // one — otherwise your own anon Moment shows in both, which reads
          // as posting it twice and undercuts the point of posting it
          // anonymously. (Someone ELSE's anon Moment was never reachable
          // here: posts' RLS already refuses it — verified live.)
          .neq('visibility', 'anonymous')
          .isFilter('deleted_at', null)
          // A Moment lasts 24h — ended ones don't show on profiles either
          // (same window as the feed, momentVisibleWindow).
          .gt('created_at', momentCutoff())
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      return (rows as List).map<FeedItem>((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return FeedItem(
          postId: m['id'] as String? ?? '',
          type: 'single',
          postType: 'moment',
          momentColor: m['moment_color'] as String?,
          userId: m['user_id'] as String? ?? '',
          caption: m['content'] as String?,
          photoUrl: m['image_url'] as String?,
          createdAt: m['created_at'] != null
              ? DateTime.tryParse(m['created_at'] as String)
              : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Ids of every Moment the caller has answered (contributed to), under
  /// either identity. Only ever used to ORDER the caller's own view, so it
  /// reveals nothing to anyone else.
  Future<Set<String>> myAnsweredMomentIds() async =>
      (await MomentService.instance.myContributedMomentIds()).toSet();

  /// Profile Moment order: Moments the viewer has answered stay on top
  /// ("if the user has answered the moment then the moment shall stay on
  /// the top"), then everything else, newest first within each group.
  static void sortMomentsAnsweredFirst(List<FeedItem> items, Set<String> answered) {
    items.sort((a, b) {
      final aa = answered.contains(a.postId);
      final bb = answered.contains(b.postId);
      if (aa != bb) return aa ? -1 : 1;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
  }

  /// Unchanged call shape for existing callers — a thin delegate onto
  /// [fetchMomentsFor] with no userId, i.e. the caller's own.
  Future<List<FeedItem>> fetchMyMoments({int limit = 50}) =>
      fetchMomentsFor(limit: limit);

  /// Moments the caller has actually CONTRIBUTED A PHOTO to, newest
  /// contribution first — real `moment_replies` rows (migration
  /// 20260910000000), not the comment-based approximation this used before
  /// that table existed.
  ///
  /// Still two steps: the RPC returns contributed post ids, then those are
  /// resolved to Moment rows. PostgREST can't join moment_replies -> posts
  /// filtered on post_type in one call without an FK-embed that isn't
  /// exposed. Fails closed to [], same as every other fetch here.
  ///
  /// [userId] is accepted for call-shape compatibility but only the
  /// caller's own contributions are readable — my_contributed_moment_ids is
  /// keyed on auth.uid(), and moment_replies' RLS exposes nobody else's
  /// rows. Passing another user's id returns [].
  /// [anonymous] selects which identity the contributions were made under —
  /// see MomentService.myContributedMomentIds. The profile's Moments tab
  /// passes false and its Anon tab passes true, so an anonymous
  /// contribution is never listed under the person's own name.
  Future<List<FeedItem>> fetchContributedMoments({
    String? userId,
    bool? anonymous,
    int limit = 50,
  }) async {
    try {
      final uid = userId ?? await CurrentUserService.instance.resolveId();
      final me = await CurrentUserService.instance.resolveId();
      if (uid != me) return [];

      // Built from MY REPLIES, not from the parent Moments. It used to list
      // the parent posts filtered to `deleted_at IS NULL`, so the moment's
      // author removing their Moment silently took every contributor's row
      // off their profile too — "if the main sender removes the moment,
      // the others shall not be removed". A reply the person removed from
      // their profile (hidden_from_profile) is left out here and nowhere
      // else. The 24h lifetime Moments have follows the reply's own time.
      final cutoff = DateTime.parse(momentCutoff());
      final replies = (await MomentService.instance.myProfileReplies(
        anonymous: anonymous,
      ))
          .where((r) {
            final at = DateTime.tryParse(r['created_at'] as String? ?? '');
            return at != null && at.isAfter(cutoff);
          })
          .take(limit)
          .toList();
      if (replies.isEmpty) return [];

      // Parent details (caption, colour, author) where the Moment is still
      // up; a removed one simply isn't returned and the row falls back to
      // the reply alone.
      final parentIds = {
        for (final r in replies)
          if (r['moment_post_id'] != null) r['moment_post_id'] as String,
      }.toList();
      final parents = parentIds.isEmpty
          ? const []
          : await _sb
              .from('posts')
              .select('id, user_id, content, moment_color')
              .inFilter('id', parentIds)
              .isFilter('deleted_at', null)
              .timeout(const Duration(seconds: 10));
      final byId = <String, Map<String, dynamic>>{
        for (final p in parents)
          (p as Map)['id'] as String: Map<String, dynamic>.from(p),
      };

      return [
        for (final r in replies)
          FeedItem(
            postId: byId.containsKey(r['moment_post_id'])
                ? r['moment_post_id'] as String
                : '',
            type: 'single',
            postType: 'moment',
            momentColor: byId[r['moment_post_id']]?['moment_color'] as String?,
            userId: byId[r['moment_post_id']]?['user_id'] as String? ?? '',
            caption: byId[r['moment_post_id']]?['content'] as String?,
            // MY contribution is what this profile row shows.
            photoUrl: r['photo_url'] as String?,
            createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
            momentReplyId: r['id'] as String,
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// The caller's own anonymous posts, newest first — the profile's Anon
  /// tab archive. Unlike fetchAnonFeed (the 24h browse feed), this has no
  /// anonCutoff filter: it's your own history, not a rotating public feed.
  /// Reads posts_feed like fetchAnonFeed does, but the view's CASE only
  /// masks user_id for rows the caller doesn't own (see its definition),
  /// so a query filtered to your own id gets a real, matchable id back.
  Future<List<FeedItem>> fetchMyAnonPosts({int limit = 50}) async {
    try {
      final userId = await CurrentUserService.instance.resolveId();
      final rows = await _sb
          .from('posts_feed')
          .select()
          .eq('visibility', 'anonymous')
          .eq('user_id', userId)
          // Anonymous Dips stay; an anonymous MOMENT still ends after 24h.
          .or('post_type.is.null,post_type.neq.moment,'
              'created_at.gt.${momentCutoff()}')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      final items = (rows as List)
          .map<FeedItem>(
            (r) => _postItemFromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
      // Posters resolved in one batched read — see _attachAuthors. Without
      // it every card in this feed renders as "someone".
      return _attachAuthors(items);
    } catch (_) {
      return [];
    }
  }

  /// Real GROUP posts for the Everyone/Friends feed — every group_posts row
  /// from a group the caller belongs to, mapped to the same FeedItem shape
  /// individual posts use so EveryonePostCard's existing groupName support
  /// (see FeedItem.groupName's own doc) renders them with zero widget
  /// changes. communityTag is always null: groups have no community concept
  /// in this schema (no community_id column on `groups`), unlike the demo
  /// placeholders this replaces which had a fabricated one.
  /// [excludeReacted]: same "once reacted, never show it again" rule as the
  /// other feeds, but keyed on [reactedGroupPostIds] — group posts live in
  /// their own table and are referenced by group_post_id, a separate id
  /// namespace from `posts`.
  Future<List<FeedItem>> fetchGroupFeed({
    int limit = 30,
    int offset = 0,
    bool excludeReacted = true,
  }) async {
    try {
      final reacted = excludeReacted
          ? await reactedGroupPostIds()
          : const <String>{};
      final rows = await GroupService.instance.fetchFeedPosts(
        limit: limit,
        offset: offset,
      );
      return rows
          .where((r) {
            if (reacted.isEmpty) return true;
            final id = r['id'] as String?;
            return id == null || !reacted.contains(id);
          })
          .map((r) {
            final group = r['groups'] as Map?;
            final user = r['users'] as Map?;
            return FeedItem(
              postId: r['id'] as String? ?? '',
              type: 'single',
              userId: r['user_id'] as String? ?? '',
              // Prefer the real username; fall back to `name` for rows
              // created before the username column existed.
              username: (user?['username'] as String?) ?? user?['name'] as String?,
              avatarUrl: user?['profile_photo_url'] as String?,
              caption: r['caption'] as String?,
              photoUrl: r['photo_url'] as String?,
              photos: (r['photo_urls'] as List?)?.cast<String>(),
              videoUrl: r['video_url'] as String?,
              videoMs: (r['video_duration_ms'] as num?)?.toInt(),
              createdAt: r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null,
              groupId: r['group_id'] as String?,
              groupName: group?['name'] as String?,
              groupIconUrl: group?['icon_url'] as String?,
              aspectRatio: r['aspect_ratio'] as String?,
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Friends-feed counterpart to [fetchGroupFeed] — group posts the poster
  /// opened up via a Friends and/or Community audience (group_post_
  /// audiences), shown to a qualifying viewer even if they aren't a member
  /// of that group. Backed by the group_post_audience_feed RPC, which
  /// returns the group/user join flattened already (see its own doc for
  /// why: group_posts/groups/users all RLS-restrict SELECT to group
  /// members, which a friends/community-path viewer isn't).
  Future<List<FeedItem>> fetchFriendsGroupFeed({
    int limit = 20,
    int offset = 0,
    // Same ruling as fetchFriendsFeed's own — this is the group-post half
    // of the same Friends feed, so it must not apply an exclusion the
    // personal-post half no longer does.
    bool excludeReacted = false,
  }) async {
    try {
      final reacted = excludeReacted
          ? await reactedGroupPostIds()
          : const <String>{};
      final rows = await _sb
          .rpc(
            'group_post_audience_feed',
            params: {'p_limit': limit, 'p_offset': offset},
          )
          .timeout(const Duration(seconds: 10));

      return (rows as List)
          .where((r) {
            if (reacted.isEmpty) return true;
            final id = (r as Map)['id'] as String?;
            return id == null || !reacted.contains(id);
          })
          .map<FeedItem>((r) {
            final m = Map<String, dynamic>.from(r as Map);
            return FeedItem(
              postId: m['id'] as String? ?? '',
              type: 'single',
              userId: m['user_id'] as String? ?? '',
              username: (m['username'] as String?) ?? m['name'] as String?,
              avatarUrl: m['avatar_url'] as String?,
              caption: m['caption'] as String?,
              photoUrl: m['photo_url'] as String?,
              photos: (m['photo_urls'] as List?)?.cast<String>(),
              createdAt: m['created_at'] != null
                  ? DateTime.tryParse(m['created_at'] as String)
                  : null,
              groupId: m['group_id'] as String?,
              groupName: m['group_name'] as String?,
              groupIconUrl: m['group_icon_url'] as String?,
              aspectRatio: m['aspect_ratio'] as String?,
              groupPostLocked: m['locked'] == true,
              groupIsPublic: m['group_is_public'] == true,
              groupSharedVia: m['shared_via'] as String?,
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Paginated anonymous-feed posts, via `posts_feed` (masks user_id for
  /// anon rows the same way [PostService.myAnonymousPosts] relies on) —
  /// AnonymousTab had zero backend query before this; it rendered only the
  /// hardcoded `_kPosts` demo list.
  /// Applies BOTH anon-feed rules:
  ///   * 24-HOUR WINDOW — `created_at > now-24h` ([anonVisibleWindow]), so
  ///     anonymous posts drop out of the feed exactly a day after posting.
  ///     Done server-side (a real `gt` on the query) rather than
  ///     client-side, so expired rows never even cross the wire and
  ///     pagination offsets stay meaningful.
  ///   * ALREADY-REACTED — filtered client-side, same reasoning as
  ///     [fetchEveryoneFeed]'s own note (unbounded id set vs. URL length).
  ///
  /// [throwOnError]: by default this fails SOFT (returns []) — the legacy
  /// AnonymousTab caller relies on that. But an empty list is then
  /// indistinguishable from "genuinely no more posts", which makes a
  /// transient query failure (e.g. a bad-UUID cast blowing up the range
  /// query) look exactly like the end of the feed: the caller stops
  /// paginating forever, and if it was the FIRST page, renders an empty
  /// feed. Callers that paginate should pass true and handle the throw, so
  /// they can keep the last good page and simply stop advancing.
  Future<List<Map<String, dynamic>>> fetchAnonFeed({
    int limit = 20,
    int offset = 0,
    bool excludeReacted = true,
    bool throwOnError = false,
  }) async {
    try {
      // Skips both reacted AND pinged posts — see _skipPostIds's own doc.
      // "excludeReacted" is the existing parameter name every caller
      // already passes; kept as-is rather than renamed, since it's still
      // the one flag that turns BOTH exclusions on or off together.
      final reacted = excludeReacted
          ? await _skipPostIds()
          : const <String>{};
      final rows = await _sb
          .from('posts_feed')
          .select()
          .eq('visibility', 'anonymous')
          // A post with no prompt attached has no context — nothing telling
          // the viewer what it's answering. Explicit request: "remove the
          // posts in the anon feed which do not have a peaking prompt".
          // Checked on `prompt` (the free text actually shown under the
          // photo), not `prompt_id` — 28 of 44 promptless-by-FK posts still
          // carry real prompt text from before prompts were properly
          // linked to daily_prompts, and hiding those too would have gutted
          // the feed from 49 posts down to 5.
          .not('prompt', 'is', null)
          .neq('prompt', '')
          // Same two-stretch rule as the Everyone/Friends feed: fresh, or
          // resurfaced. See resurfaceAfter.
          .or('created_at.gt.${anonCutoff()},'
              'created_at.lt.${resurfaceCutoff()}')
          // ...except a Moment, which ends after 24h and never resurfaces.
          .or('post_type.neq.moment,created_at.gt.${momentCutoff()}')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 10));
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (reacted.isEmpty) return list;
      return list.where((r) {
        final id = r['id'] as String?;
        return id == null || !reacted.contains(id);
      }).toList();
    } catch (_) {
      if (throwOnError) rethrow;
      return [];
    }
  }

  /// The Dip feed's safety net ("the dip feed shall never be empty"): used
  /// only when [fetchAnonFeed] has nothing left to show AND nothing is on
  /// screen. Same source and masking (`posts_feed`) and the same
  /// prompt-required rule, but without the freshness window or the
  /// reacted/pinged exclusion, so older Dips fill the feed instead of an
  /// empty state. Still RLS-gated like every other read.
  Future<List<Map<String, dynamic>>> fetchAnonFallback({int limit = 20}) async {
    try {
      final rows = await _sb
          .from('posts_feed')
          .select()
          .eq('visibility', 'anonymous')
          .not('prompt', 'is', null)
          .neq('prompt', '')
          // Older Dips, yes; ended Moments, never.
          .or('post_type.neq.moment,created_at.gt.${momentCutoff()}')
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  /// One post by id, as a fully-populated [FeedItem] — the deep-link path
  /// for a notification tap ("X reacted to your post" -> that post).
  ///
  /// Goes through `posts_feed`, not `posts`: an anonymous post must arrive
  /// with its author masked exactly as it would in any feed, and that view
  /// is the only read path that does the masking. Tapping a notification
  /// about your own anon post must not become the one place the app hands
  /// back a real user_id.
  ///
  /// Returns null when the post is gone (deleted, or expired out of the
  /// anon window) — callers treat that as "fall back to the feed" rather
  /// than opening an empty detail screen.
  Future<FeedItem?> fetchPostById(String postId) async {
    try {
      final row = await _sb
          .from('posts_feed')
          .select()
          .eq('id', postId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return null;
      final item = _postItemFromRow(Map<String, dynamic>.from(row));
      final withAuthors = await _attachAuthors([item]);
      return withAuthors.isEmpty ? null : withAuthors.first;
    } catch (_) {
      return null;
    }
  }

}
