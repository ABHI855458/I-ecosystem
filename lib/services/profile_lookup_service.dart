import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/profile_v2/profile_v2_data.dart';
import 'ping_service.dart';

// ---------------------------------------------------------------------------
// ProfileLookupService — resolves a `users.id` (the id every comment/
// reaction/realmoji/post row already carries — see CurrentUserService's own
// doc on the users/profiles duality) into the shape TheirProfileScreen
// needs. Read-only, single-row lookups; no caching — avatar taps are
// infrequent enough that this doesn't need to be optimized yet.
// ---------------------------------------------------------------------------

class ProfileLookupService {
  ProfileLookupService._();
  static final instance = ProfileLookupService._();

  final _client = Supabase.instance.client;

  /// Null if the id doesn't resolve to a real row (e.g. a demo/synthetic id
  /// from a not-yet-real data source like live presence — see
  /// post_card_shared.dart's demoLivePresence doc).
  Future<PersonProfile?> fetchById(String userId) async {
    try {
      // Fetched alongside the profile row rather than after it: the streak
      // is rendered in the same first frame as the name, so a second
      // round trip would show a 0 that silently corrects itself.
      final streaks = await PingService.instance.fetchStreaks();
      final row = await _client
          .from('users')
          .select(
            'name, department, bio, glow_score, ping_score, profile_photo_url, banner_url, campus',
          )
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      final name = row['name'] as String? ?? 'someone';
      return PersonProfile(
        name: name,
        // NOT users.anon_name — that's the person's separate Anon-feed
        // persona; showing it here would leak anon identity into the named
        // profile view, exactly what TheirProfileScreen's own doc says this
        // screen must never do. Sanitized from `name` instead: seed/demo
        // rows are already single-token ('study_bug') so this is a no-op
        // for them, but a real account's full name ('Abhishek SD Patel')
        // needs it to avoid a handle with spaces in it.
        handle: '@${_handleize(name)}',
        // Real, derived server-side from this account's own email domain
        // (20261001020000_derive_campus_from_email.sql) — empty for the
        // outsider accounts 20260929070000_allow_any_email_domain.sql now
        // allows in, not the old hardcoded 'RVCE' fake-for-everyone value.
        campus: (row['campus'] as String?) ?? '',
        bio: (row['bio'] as String?) ?? '',
        anonScore: (row['glow_score'] as num?)?.toInt() ?? 0,
        pingScore: (row['ping_score'] as num?)?.toInt() ?? 0,
        // The REAL pairwise streak with this person — how many consecutive
        // days the two of you have kept a ping going (ping_streak_with,
        // surfaced by my_ping_streaks).
        //
        // This was hardcoded 0 with a note saying no pairwise streak
        // existed in the backend. It did: the Ping page has been reading
        // exactly this to draw its per-friend streak flames. So every
        // profile's streak hero — the biggest tile on the page — read "0
        // days" for everyone, including people you ping daily.
        pairStreak: streaks[userId] ?? 0,
        userId: userId,
        avatarUrl: row['profile_photo_url'] as String?,
        bannerUrl: row['banner_url'] as String?,
      );
    } catch (e) {
      return null;
    }
  }

  String _handleize(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
}
