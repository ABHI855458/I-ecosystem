import '../core/supabase_config.dart';

// ---------------------------------------------------------------------------
// CommunityService — the communities the signed-in user belongs to, WITH
// their names.
//
// `community_members` (keyed on the raw auth uid, per mem_join's RLS
// `WITH CHECK (user_id = auth.uid())`) is the only membership table now.
// `user_communities` — a dead duplicate with 0 live rows, keyed on
// `users.id` instead — was dropped 2026-09-04; this file used to read both
// and merge/dedupe the results.
//
// NO-FK FIX (2026-09-04): a `community_members.community_id ->
// communities(id)` FK now exists live, added in the same pass as the
// table drop above specifically so this can use a normal PostgREST embed.
// Before that FK existed, `.select('community_id, communities(...)')`
// threw PGRST200 ("no relationship found") on every call, which is why
// this used to do a manual two-step join (ids first, then a communities
// lookup) instead.
// ---------------------------------------------------------------------------

class CommunityOption {
  const CommunityOption({required this.id, required this.name, this.iconUrl});

  final String id;
  final String name;
  final String? iconUrl;
}

/// One member of a community the caller has joined — for the Ping page's
/// "everyone in your communities" list, distinct from the Friends row above
/// it (accepted friends only).
class CommunityMember {
  const CommunityMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
}

class CommunityService {
  CommunityService._();
  static final instance = CommunityService._();

  /// Empty list when nobody is signed in or the member has joined nothing —
  /// a real, distinct state from an outright read error, which throws.
  Future<List<CommunityOption>> fetchMyCommunities() async {
    final authId = supabase.auth.currentUser?.id;
    if (authId == null) return [];

    // BUG FIX (found during the Wake-pilot community reduction's own
    // verification pass): `!inner` + the deleted_at filter on the embedded
    // resource — without it this returned a row for EVERY community the
    // caller had ever joined, including ones since soft-deleted. Verified
    // live: one real account carried 20+ stale memberships in communities
    // deactivated for the 6-community pilot (Football, Martial Arts,
    // Singers, ...), all of which still surfaced here — in the Community
    // tab's own chip strip AND in composer_screen.dart's "Also show to"
    // picker (this method backs both, see fetchJoinedCommunities's own
    // doc). Deactivating a community never touched community_members rows
    // (by design, so a re-activation loses no membership history), but
    // nothing here was filtering them back out on read.
    final rows = await supabase
        .from('community_members')
        .select('community_id, communities!inner(id, name, icon_url)')
        .eq('user_id', authId)
        .isFilter('communities.deleted_at', null)
        .timeout(const Duration(seconds: 10));

    final out = <String, CommunityOption>{};
    for (final r in rows as List) {
      final c = (r as Map)['communities'] as Map?;
      final id = c?['id'] as String?;
      final name = c?['name'] as String?;
      if (id != null && name != null) {
        out[id] = CommunityOption(id: id, name: name, iconUrl: c?['icon_url'] as String?);
      }
    }
    final list = out.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Same result as [fetchMyCommunities] under a name that matches the rest
  /// of this feature's naming (community_screen.dart's chip strip, the
  /// join/leave manage sheet). Kept as a separate method rather than
  /// renaming fetchMyCommunities, which composer_screen.dart:1327 already
  /// depends on by that name.
  Future<List<CommunityOption>> fetchJoinedCommunities() => fetchMyCommunities();

  /// Every member of every community the caller has joined, deduped, self
  /// excluded — backs the Ping page's "everyone in your communities" list.
  /// An RPC because community_members.user_id stores the AUTH id, not
  /// users.id, so there is no FK for PostgREST to embed users(*) through.
  Future<List<CommunityMember>> fetchMyCommunityMembers() async {
    if (supabase.auth.currentUser == null) return [];
    final rows = await supabase
        .rpc('my_community_members_for_ping')
        .timeout(const Duration(seconds: 10));
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      final username = (r['username'] as String?)?.trim();
      final name = (r['name'] as String?)?.trim();
      return CommunityMember(
        userId: r['user_id'] as String,
        displayName: (username != null && username.isNotEmpty)
            ? username
            : (name != null && name.isNotEmpty ? name : 'someone'),
        avatarUrl: r['avatar_url'] as String?,
      );
    }).toList();
  }

  /// The signed-in user's BEST standing across their communities — the one
  /// where they place highest by xp, with that placement.
  ///
  /// Backs MyProfileScreen's "BEST COMMUNITY STANDING" card, which used to
  /// render PV2Data.me's mock "#3 · Design Club" on every account (the
  /// schema genuinely had no best_rank column, so it was left as filler).
  /// `community_streaks(community_id, user_id, xp)` IS a real ranking
  /// source — the same table award_community_reaction_xp() writes to — so
  /// the rank is computed from it here rather than stored.
  ///
  /// RLS does the scoping for free: community_streaks_select only returns
  /// rows for communities the caller is actually a member of, so this reads
  /// every row it can see and groups client-side. Null when the user has no
  /// xp anywhere yet — the caller hides the card rather than showing a
  /// fabricated placement.
  Future<({int rank, String communityName, int communityCount})?>
  fetchBestCommunityStanding(String myUserId) async {
    final rows = await supabase
        .from('community_streaks')
        .select('community_id, user_id, xp, communities(name)')
        .timeout(const Duration(seconds: 10));

    // community_id -> every (user_id, xp) row visible for it.
    final byCommunity = <String, List<({String userId, int xp})>>{};
    final names = <String, String>{};
    for (final r in rows as List) {
      final m = r as Map;
      final cid = m['community_id'] as String?;
      final uid = m['user_id'] as String?;
      if (cid == null || uid == null) continue;
      (byCommunity[cid] ??= []).add((
        userId: uid,
        xp: (m['xp'] as num?)?.toInt() ?? 0,
      ));
      final name = (m['communities'] as Map?)?['name'] as String?;
      if (name != null) names[cid] = name;
    }

    ({int rank, String communityName, int xp})? best;
    for (final entry in byCommunity.entries) {
      final members = entry.value..sort((a, b) => b.xp.compareTo(a.xp));
      final index = members.indexWhere((m) => m.userId == myUserId);
      if (index < 0) continue;
      final candidate = (
        rank: index + 1,
        communityName: names[entry.key] ?? 'a community',
        xp: members[index].xp,
      );
      // Best = highest placement; a tie on placement goes to more xp.
      if (best == null ||
          candidate.rank < best.rank ||
          (candidate.rank == best.rank && candidate.xp > best.xp)) {
        best = candidate;
      }
    }

    if (best == null) return null;
    return (
      rank: best.rank,
      communityName: best.communityName,
      communityCount: byCommunity.length,
    );
  }

  /// Every community the moderator dashboard has published — the DISCOVER
  /// side of the manage sheet. Read-only: this app has no create/edit/
  /// delete path for a community, by design (communities_insert/update/
  /// delete_moderator all require an admin or global_moderator row; the
  /// app-side concept the user owns is *membership*, not the community
  /// itself).
  Future<List<CommunityOption>> fetchAllCommunities() async {
    final rows = await supabase
        .from('communities')
        .select('id, name, icon_url')
        .isFilter('deleted_at', null)
        .order('name')
        .timeout(const Duration(seconds: 10));
    return (rows as List)
        .map((r) => CommunityOption(
              id: (r as Map)['id'] as String,
              name: r['name'] as String,
              iconUrl: r['icon_url'] as String?,
            ))
        .toList();
  }

  /// Joins a community for the current user. Writes `community_members`,
  /// keyed on auth.uid() per mem_join's RLS.
  Future<void> joinCommunity(String communityId) async {
    final authId = supabase.auth.currentUser?.id;
    if (authId == null) {
      throw StateError('CommunityService.joinCommunity called with no signed-in user');
    }
    await supabase.from('community_members').insert({
      'community_id': communityId,
      'user_id': authId,
    });
  }

  /// Leaves a community.
  ///
  /// `mem_leave` permits deleting your OWN membership row, except for
  /// "General" — every user is auto-joined to it and campus announcements
  /// reach them through it, so leaving is refused server-side.
  ///
  /// A refusal there arrives as zero rows deleted, not an error (the
  /// standing failure mode on this project), so this checks the result and
  /// throws rather than reporting a success that didn't happen.
  Future<void> leaveCommunity(String communityId) async {
    final authId = supabase.auth.currentUser?.id;
    if (authId == null) {
      throw StateError('CommunityService.leaveCommunity called with no signed-in user');
    }
    final rows = await supabase
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', authId)
        .select('community_id');
    if ((rows as List).isEmpty) {
      throw StateError("You can't leave this community.");
    }
  }
}
