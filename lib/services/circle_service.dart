import '../core/supabase_config.dart';
import 'block_service.dart';
import 'current_user_service.dart';
import 'feed_refresh_signal.dart';
import 'people_service.dart';

// ---------------------------------------------------------------------------
// CircleService — user-created private posting audiences.
//
// A circle is visible ONLY to its creator: `circles`/`circle_members` carry
// exactly one RLS policy each (creator-only), with no member-facing policy
// at all — see 20260919000000_circles_private_audiences.sql. So every read
// here is implicitly "circles I made"; there is no such thing as "circles
// I'm in" from the client's own point of view, by design. A member finds
// out they're in one only by seeing a post that circle was sent to — never
// a name, never a notification, never a row.
//
// Adding a member is enforced server-side by circle_member_is_eligible()
// (must share a community with the creator) via the INSERT's WITH CHECK —
// this fails closed, so a client bug here can narrow who can be added,
// never let through someone ineligible.
//
// Circles are also the app's whole social graph now — friend requests are
// gone (20260926000000_circles_replace_friendships.sql). Every user owns four
// presets (seeded server-side): Friends, Close Friends, Family, Roommates /
// Work. "Friend" means exactly "in my Friends circle", one-directional:
// putting someone in yours shows them YOUR friends-audience posts, never the
// reverse. Friends can't be deleted (it CAN be renamed), and adding someone to Close
// Friends also puts them in Friends (both enforced by triggers).
// ---------------------------------------------------------------------------

/// `circles.kind`. Everything but [custom] is a seeded preset.
enum CircleKind {
  friends('friends'),
  closeFriends('close_friends'),
  family('family'),
  work('work'),
  custom('custom');

  const CircleKind(this.db);
  final String db;

  static CircleKind parse(String? v) =>
      CircleKind.values.firstWhere((k) => k.db == v, orElse: () => CircleKind.custom);

  bool get isPreset => this != CircleKind.custom;
}

class CircleOption {
  const CircleOption({
    required this.id,
    required this.name,
    this.memberCount = 0,
    this.kind = CircleKind.custom,
  });

  final String id;
  final String name;
  final CircleKind kind;

  /// The compulsory circle — never deletable or renamable.
  bool get isFriends => kind == CircleKind.friends;

  /// 0 until [CircleService.fetchMyCircles] has actually loaded it — a
  /// freshly-created circle passed straight into the members screen (see
  /// ManageCirclesScreen's own doc) legitimately starts at 0, so this isn't
  /// a "still loading" sentinel, just the real count at construction time.
  final int memberCount;
}

/// One circle member — just enough to render a chip/row. Sourced by joining
/// through `users`, since `circle_members.member_id` is a `users.id`.
class CircleMember {
  const CircleMember({
    required this.userId,
    required this.name,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
}

class CircleService {
  CircleService._();
  static final instance = CircleService._();

  /// Idempotent: creates any missing preset circles for the caller. New
  /// accounts are seeded by a trigger already; onboarding calls this anyway
  /// so an account that predates the trigger can never reach the circles
  /// step without a Friends circle.
  Future<void> ensureDefaultCircles() async {
    await supabase.rpc('ensure_default_circles');
  }

  /// Circles the signed-in user created — RLS already limits this to
  /// "mine". Presets first in their fixed order (Friends, Close Friends,
  /// Family, Roommates / Work), then custom circles newest first.
  Future<List<CircleOption>> fetchMyCircles() async {
    final rows = await supabase
        .from('circles')
        .select('id, name, kind')
        .order('created_at', ascending: false);
    final ids = [for (final r in rows) r['id'] as String];
    // One extra query for every circle's roster, rather than a
    // count-per-row embed — circle_members carries no RLS a member could
    // exploit here (creator-only policy, see the migration's own doc), and
    // this keeps CircleOption's shape simple (a plain int, not a nested
    // aggregate PostgREST would otherwise hand back).
    final counts = <String, int>{};
    if (ids.isNotEmpty) {
      final memberRows = await supabase
          .from('circle_members')
          .select('circle_id')
          .inFilter('circle_id', ids);
      for (final m in memberRows) {
        final id = m['circle_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final out = [
      for (final r in rows)
        CircleOption(
          id: r['id'] as String,
          name: r['name'] as String,
          memberCount: counts[r['id'] as String] ?? 0,
          kind: CircleKind.parse(r['kind'] as String?),
        ),
    ];
    // Stable sort: presets by enum order, customs keep newest-first.
    final indexed = out.asMap().entries.toList()
      ..sort((a, b) {
        final c = a.value.kind.index.compareTo(b.value.kind.index);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  /// user_id -> ids of MY circles that person is in. One query for the
  /// whole graph, so a profile/picker can render every person's chips
  /// without an N+1.
  Future<Map<String, Set<String>>> fetchMyMembership() async {
    final myId = await CurrentUserService.instance.resolveId();
    final rows = await supabase
        .from('circle_members')
        .select('member_id, circle_id, circles!inner(creator_id)')
        .eq('circles.creator_id', myId);
    final out = <String, Set<String>>{};
    for (final r in rows) {
      (out[r['member_id'] as String] ??= <String>{}).add(r['circle_id'] as String);
    }
    return out;
  }

  /// Everyone in my Friends circle, as `users` rows (PeopleService shape).
  /// This is the "friends" list everywhere in the app now.
  Future<List<Map<String, dynamic>>> fetchFriendsCircleUsers() async {
    final myId = await CurrentUserService.instance.resolveId();
    final rows = await supabase
        .from('circle_members')
        .select('member_id, circles!inner(creator_id, kind)')
        .eq('circles.creator_id', myId)
        .eq('circles.kind', CircleKind.friends.db);
    return PeopleService.instance
        .usersByIds([for (final r in rows) r['member_id'] as String]);
  }

  /// Everyone in ANY of my circles — the pool for Duo and group-album
  /// pickers (people you've already placed somewhere, before searching).
  Future<List<Map<String, dynamic>>> fetchPeopleInMyCircles() async {
    final membership = await fetchMyMembership();
    final users = await PeopleService.instance.usersByIds(membership.keys);
    users.sort((a, b) => ((a['name'] as String?) ?? '')
        .toLowerCase()
        .compareTo(((b['name'] as String?) ?? '').toLowerCase()));
    return users;
  }

  /// Puts [memberId] in exactly [circleIds] of my circles: adds the missing
  /// ones and removes the rest. Friends is never removed implicitly just
  /// because Close Friends was added (the trigger adds it server-side).
  Future<void> setMembership(String memberId, Set<String> circleIds) async {
    final current = (await fetchMyMembership())[memberId] ?? <String>{};
    for (final id in circleIds.difference(current)) {
      await supabase.from('circle_members').insert({'circle_id': id, 'member_id': memberId});
    }
    for (final id in current.difference(circleIds)) {
      await supabase
          .from('circle_members')
          .delete()
          .eq('circle_id', id)
          .eq('member_id', memberId);
    }
    signalFeedRefresh();
  }

  Future<String> createCircle(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Circle name cannot be empty.');
    }
    final userId = await CurrentUserService.instance.resolveId();
    final row = await supabase
        .from('circles')
        .insert({'creator_id': userId, 'name': trimmed})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> renameCircle(String circleId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await supabase.from('circles').update({'name': trimmed}).eq('id', circleId);
  }

  /// Deletes the circle. `circle_members` and every `post_audiences` row
  /// pointing at it cascade (ON DELETE CASCADE) — existing posts stay up,
  /// they just lose that one audience path; anyone still able to see them
  /// through friends/community/everyone visibility is unaffected.
  Future<void> deleteCircle(String circleId) async {
    await supabase.from('circles').delete().eq('id', circleId);
  }

  /// Members of a circle the caller created. Only ever callable on your
  /// own circle — RLS returns zero rows for anything else.
  /// Same fix as [PeopleService.usersByIds] — a blocked person's actual
  /// circle membership row is untouched by blocking (that's a separate,
  /// manual relationship), so this used to keep showing their name and
  /// photo in a circle's own member list too.
  Future<List<CircleMember>> fetchMembers(String circleId) async {
    final rows = await supabase
        .from('circle_members')
        .select('member_id, users(id, name, profile_photo_url)')
        .eq('circle_id', circleId);
    final blockedIds = await BlockService.instance.blockedUserIds();
    return [
      for (final r in rows)
        if (!blockedIds.contains(r['member_id']))
          CircleMember(
            userId: r['member_id'] as String,
            name: (r['users']?['name'] as String?) ?? 'someone',
            avatarUrl: r['users']?['profile_photo_url'] as String?,
          ),
    ];
  }

  /// Throws if the member isn't eligible (no shared community with the
  /// creator) — the server is the real gate (circle_member_is_eligible via
  /// WITH CHECK); this just surfaces that as a normal exception rather than
  /// a silent no-op insert.
  ///
  /// [refreshFeed] false skips the feed-wide reload — the Friends feed's own
  /// suggestion strip adds from INSIDE the feed, and a reload there cleared
  /// and re-fetched the whole list under the user's finger ("glitching").
  Future<void> addMember(
    String circleId,
    String memberId, {
    bool refreshFeed = true,
  }) async {
    // Idempotent: someone already in the circle (a double tap, or the
    // Close Friends → Friends trigger got there first) used to 409, and the
    // UI rolled back an add that had actually happened.
    await supabase.from('circle_members').upsert(
      {'circle_id': circleId, 'member_id': memberId},
      onConflict: 'circle_id,member_id',
      ignoreDuplicates: true,
    );
    if (refreshFeed) signalFeedRefresh();
  }

  Future<void> removeMember(String circleId, String memberId) async {
    await supabase
        .from('circle_members')
        .delete()
        .eq('circle_id', circleId)
        .eq('member_id', memberId);
    signalFeedRefresh();
  }
}

/// Audience selection for a friends-visibility post, shared by every
/// "Who can see this" picker.
///
/// Server rule (post_audience_admits): if a post names circles, ONLY those
/// circles see it; if it names none, the author's Friends circle does. So
/// the empty set here means "Friends (default)" and is what gets sent for
/// the default — no rows at all.
class CircleAudience {
  const CircleAudience._();

  static String? friendsId(List<CircleOption>? circles) {
    for (final c in circles ?? const <CircleOption>[]) {
      if (c.isFriends) return c.id;
    }
    return null;
  }

  static bool isSelected(Set<String> picked, String circleId, List<CircleOption>? circles) =>
      picked.isEmpty ? circleId == friendsId(circles) : picked.contains(circleId);

  /// Toggles [circleId] in place. Deselecting the last circle falls back to
  /// the Friends default rather than leaving a post nobody can see.
  static void toggle(Set<String> picked, String circleId, List<CircleOption>? circles) {
    final f = friendsId(circles);
    final effective = picked.isEmpty && f != null ? <String>{f} : {...picked};
    if (!effective.remove(circleId)) effective.add(circleId);
    picked.clear();
    if (effective.isEmpty || (effective.length == 1 && effective.first == f)) return;
    picked.addAll(effective);
  }
}
