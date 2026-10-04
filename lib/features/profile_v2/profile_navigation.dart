import 'package:flutter/material.dart';

import '../../shared/nav_guard.dart';
import '../../services/current_user_service.dart';
import '../../services/profile_lookup_service.dart';
import 'my_profile_screen.dart';
import 'their_profile_screen.dart';

// ---------------------------------------------------------------------------
// Global profile routing — the single entry point every avatar tap in the
// Friends/Everyone feed (post cards, comments, reactions, live-here) goes
// through. Deliberately NOT wired into the Anon feed anywhere (that feed's
// avatars/names stay non-tappable, by design — see anon_feed_v2's own
// no-identity rules).
// ---------------------------------------------------------------------------

/// Opens [userId]'s profile — MyProfileScreen if it's the signed-in user's
/// own id, TheirProfileScreen (real data, not PV2Data mock) otherwise. Shows
/// a brief snackbar instead of navigating if the id doesn't resolve to a
/// real `users` row (e.g. a still-synthetic id from a not-yet-real data
/// source like live presence).
Future<void> openProfile(BuildContext context, String userId) =>
    // Guarded: this function awaits up to two network calls before it
    // pushes, so without it a double tap opens the same profile twice.
    NavGuard.run(() => _openProfile(context, userId));

Future<void> _openProfile(BuildContext context, String userId) async {
  final ownId = await CurrentUserService.instance.resolveId();
  if (!context.mounted) return;

  if (userId == ownId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyProfileScreen()),
    );
    return;
  }

  final person = await ProfileLookupService.instance.fetchById(userId);
  if (!context.mounted) return;

  if (person == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't find that profile.")),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TheirProfileScreen(person: person)),
  );
}
