import 'package:supabase_flutter/supabase_flutter.dart';

import 'current_user_service.dart';
import 'post_author_pin_service.dart';
import 'post_service.dart';

// ---------------------------------------------------------------------------
// PresenceService — real reads/writes against the live `post_presence`
// table (see supabase/migrations/20260905000000_post_presence.sql). Backs
// the "N here" pill + dropdown (LivePresencePill/LivePresenceDropdown in
// post_card_shared.dart), which previously rendered demoLivePresence()'s
// hash-seeded fake names — there was no presence backend at all.
//
// [postId]/[groupPostId] are mutually exclusive on every call, mirroring
// CommentService/comments' own post_id XOR group_post_id split — group
// posts (design_group_card.dart / group_card_shared.dart) live in
// `group_posts`, not `posts`.
// ---------------------------------------------------------------------------

class PresenceEntry {
  const PresenceEntry({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.lastSeenAt,
    required this.isPinned,
    this.viewedOnly = false,
    this.notSeen = false,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final DateTime lastSeenAt;

  /// Whether the CURRENT (viewing) user has pinned this person — pinned
  /// entries sort to the top of the list, ahead of anyone more recently
  /// seen. See PostAuthorPinService.pinnedIds.
  final bool isPinned;

  /// True for a pinned person who has no live/recent presence row at all —
  /// [lastSeenAt] here is when they OPENED the post (post_views), not a
  /// heartbeat. Explicit instruction: "even if the pinned person has not
  /// been there at the current moment, if they have viewed it, it shall be
  /// showing in the here section" — this is what makes that entry exist at
  /// all, since a presence-only read would never produce one. Always false
  /// for a non-pinned entry: the "seen but not here, no time limit" rule is
  /// pinned-only, same as the presence-window bypass it extends.
  final bool viewedOnly;

  /// True for a pinned person who has neither a presence row NOR a view —
  /// they have not opened this post at all. Explicit instruction: the
  /// dropdown "shall show the pinned people if they have viewed or not",
  /// so a pinned person is now always listed and the list itself says
  /// which of the two they are. [lastSeenAt] is meaningless for these (it
  /// is epoch 0) and nothing may read it as a time.
  ///
  /// Mutually exclusive with [viewedOnly], and pinned-only for the same
  /// reason [viewedOnly] is: listing every non-pinned person who has NOT
  /// seen a post would be the whole campus.
  final bool notSeen;

  /// "Here now" vs "last 3 hours" is purely this cutoff — both buckets come
  /// from the same fetch, split client-side. A [viewedOnly] entry is never
  /// "here now" even if [lastSeenAt] happens to be recent — see
  /// LivePresenceDropdown, which checks viewedOnly before this.
  bool get isHereNow =>
      !viewedOnly &&
      !notSeen &&
      DateTime.now().difference(lastSeenAt) < const Duration(minutes: 2);
}

class PresenceService {
  PresenceService._();
  static final instance = PresenceService._();

  final _sb = Supabase.instance.client;

  /// Client-side throttle so a card that stays on screen doesn't hammer the
  /// RPC every frame — one write per post per ~30s is plenty for a
  /// heartbeat this coarse (the dropdown itself only distinguishes "now"
  /// from "within 3h").
  final Map<String, DateTime> _lastTouch = {};

  /// Marks the current user as present on [postId] or [groupPostId]
  /// (exactly one required). Fire-and-forget from every call site — a
  /// missed heartbeat just means this user drops out of the list a little
  /// early, never a crash.
  Future<void> touch({String? postId, String? groupPostId}) async {
    assert(
      (postId == null) != (groupPostId == null),
      'PresenceService.touch: pass exactly one of postId / groupPostId',
    );
    final key = postId ?? groupPostId!;
    final last = _lastTouch[key];
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastTouch[key] = DateTime.now();
    try {
      await _sb.rpc(
        'touch_post_presence',
        params: {
          if (postId != null) 'p_post_id': postId,
          if (groupPostId != null) 'p_group_post_id': groupPostId,
        },
      );
    } catch (_) {
      // Non-critical — see doc above.
    }
  }

  /// Everyone present on [postId] or [groupPostId] (exactly one required)
  /// within the last 3 hours. Real ids/names/avatars — callers split into
  /// "here now" (see PresenceEntry.isHereNow) vs "last 3 hours" themselves.
  ///
  /// Ordering: pinned people (see PostAuthorPinService) first, then
  /// most-recent-heartbeat first within each of those two groups — a
  /// stable partition, not a sort, so "pinned" never reorders people
  /// relative to each other by recency. Sorted client-side rather than via
  /// a join so the underlying RLS-shaped query at `:87` stays untouched.
  Future<List<PresenceEntry>> fetchPresence({
    String? postId,
    String? groupPostId,
  }) async {
    assert(
      (postId == null) != (groupPostId == null),
      'PresenceService.fetchPresence: pass exactly one of postId / groupPostId',
    );
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 3));

      // Pins are resolved BEFORE the presence query, not alongside it,
      // because they change what that query is allowed to exclude: a PINNED
      // person is shown however long ago they were last seen, while everyone
      // else is held to the 3-hour window. Explicit instruction — "even if
      // they have visited, no time limit to show the pinned people". The
      // previous version applied .gte(cutoff) unconditionally, so a pinned
      // person last seen 4 hours ago was dropped by the query and could
      // never reach the pinned bucket below.
      //
      // Both lookups still fail soft: no pins (or a failed pin fetch) simply
      // falls back to the plain 3-hour window, which is exactly the old
      // behaviour. My own id is fetched for the same reason [touch] wrote a
      // row for me in the first place — see the exclusion below.
      final pre = await Future.wait<dynamic>([
        PostAuthorPinService.instance.pinnedIds().catchError((_) => <String>{}),
        CurrentUserService.instance.resolveId().catchError((_) => ''),
      ]);
      final pinnedIds = pre[0] as Set<String>;
      final myId = pre[1] as String;

      // post_presence_people (20260927290000_pin_privacy_masking.sql) is the
      // only way to read others' presence: it applies the post's visibility
      // gate, drops my own row, keeps pinned people at any age, and masks
      // everyone I haven't pinned (no id/name/photo, just an opaque
      // viewer_key) so nobody can learn who is pinned by whom.
      final rows = await _sb
          .rpc(
            'post_presence_people',
            params: {
              if (postId != null) 'p_post_id': postId,
              if (groupPostId != null) 'p_group_post_id': groupPostId,
              'p_since': cutoff.toIso8601String(),
            },
          )
          .timeout(const Duration(seconds: 8));

      final entries = (rows as List)
          .cast<Map<String, dynamic>>()
          .map((r) {
            final pinned = r['is_pinned'] as bool? ?? false;
            // Real names for everyone now (20260928100000) — the "here"
            // pill shows who was actually on the post.
            return PresenceEntry(
              userId: (r['user_id'] as String?) ?? 'k:${r['viewer_key']}',
              name: (r['name'] as String?) ?? 'someone',
              avatarUrl: r['avatar_url'] as String?,
              lastSeenAt: DateTime.parse(r['last_seen_at'] as String),
              isPinned: pinned,
            );
          })
          .toList();

      // VIEWS, merged into presence. post_presence only records live
      // heartbeats, so on its own the panel could only ever describe who
      // happened to be holding the post open — someone who opened it,
      // read it and left thirty minutes ago left no trace. post_views
      // (and group_post_views) is the permanent record of who actually
      // opened it, and the two answer different halves of the same
      // question, so both feed the same list.
      //
      // Two different rules, deliberately:
      //
      //   * PINNED people are merged at ANY age. Explicit instruction —
      //     "even if the pinned person has not been there at the current
      //     moment, if they have viewed it, it shall be showing". They
      //     land in PINNED · SEEN (viewedOnly), which never claims recent
      //     presence the way the other sections do.
      //
      //   * EVERYONE ELSE is merged only if they opened it inside the same
      //     3-hour window the presence query uses, so they sit truthfully
      //     under LAST 3 HOURS. Without an age bound this section would
      //     accumulate every viewer the post ever had under a header that
      //     says "last 3 hours".
      //
      // Runs unconditionally now. It used to be gated on the caller having
      // pins at all, which meant a viewer with no pinned people saw an
      // empty panel no matter how many people had opened their post.
      try {
        final presentIds = entries.map((e) => e.userId).toSet();
        // Group posts have their own views table and their own viewers
        // RPC (group_post_viewers), same shape, same is_pinned column.
        // This was once gated on `postId != null` on the assumption that
        // group posts had no views infrastructure — they do, so a pinned
        // person who had opened a GROUP post never appeared and the group
        // card's pill fell through to "only you".
        final viewers = postId != null
            ? await PostService.instance.fetchPostViewers(postId)
            : await PostService.instance.fetchGroupPostViewers(groupPostId!);
        for (final v in viewers) {
          // Self-exclusion matters here in a way it did not before. The
          // old merge only ever added PINNED people, and nobody can pin
          // themselves, so the caller could never slip in. Now that
          // ordinary viewers are merged too, the caller's own view row
          // would otherwise put them in their own "here" list — the exact
          // "1 here that is really just me" bug the presence query above
          // already guards against.
          if (v.userId == myId || presentIds.contains(v.userId)) continue;

          if (v.isPinned) {
            entries.add(
              PresenceEntry(
                userId: v.userId,
                name: v.displayName,
                avatarUrl: v.avatarUrl,
                lastSeenAt:
                    v.viewedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                isPinned: true,
                viewedOnly: true,
              ),
            );
          }
          // Unpinned recent viewers are NOT merged here any more:
          // post_presence_people already returns everyone who opened the
          // post inside the window, WITH real names (20260928100000).
          // These rows come masked ("someone in CS", for the seen pill)
          // and would list the same person a second time.
        }
      } catch (_) {
        // Merge is additive — a failed fetch just means this call returns
        // what presence alone already had.
      }

      if (pinnedIds.isNotEmpty) {

        // ...and finally the pinned people who are in NEITHER list: no
        // presence row and no view, i.e. they have not opened this post.
        // Explicit instruction — the dropdown "shall show the pinned people
        // if they have viewed or not". Without this pass a pinned person
        // simply vanished from the panel until the moment they opened the
        // post, so "who of my pinned people has seen this" could only ever
        // be answered by remembering who was missing.
        //
        // Names/avatars come from list_pinned_people() rather than a
        // `users` select: these people have no row in either source above,
        // so there is nothing to read a name off, and `pinned_people` has
        // RLS with no client policies — that RPC is the only way in.
        //
        // Applies to group posts too, for the same reason the merge above
        // now does: group_post_views makes "seen" a real, answerable fact
        // there, so "not seen" is a real one as well.
        try {
          final known = entries.map((e) => e.userId).toSet();
          final pinnedPeople = await PostAuthorPinService.instance.listPinned();
          for (final row in pinnedPeople) {
            final uid = row['pinned_user_id'] as String?;
            if (uid == null || uid == myId || known.contains(uid)) continue;
            entries.add(
              PresenceEntry(
                userId: uid,
                name: (row['name'] as String?) ?? 'someone',
                avatarUrl: row['profile_photo_url'] as String?,
                lastSeenAt: DateTime.fromMillisecondsSinceEpoch(0),
                isPinned: true,
                notSeen: true,
              ),
            );
          }
        } catch (_) {
          // Same additive contract as the merge above.
        }
      }

      final pinned = entries.where((e) => e.isPinned).toList();
      final rest = entries.where((e) => !e.isPinned).toList();
      return [...pinned, ...rest];
    } catch (_) {
      return const [];
    }
  }
}
