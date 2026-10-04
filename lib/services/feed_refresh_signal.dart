import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// feedRefreshSignal — "what a feed query would return has changed".
//
// The audience gate is evaluated LIVE on every query: fetchEveryoneFeed reads
// `posts` and RLS runs can_view_post() per row, and the friends-audience
// group feed uses the same in_friends_circle() check. Nothing is cached, so
// a circle change genuinely does change what's visible the
// instant the row lands — verified against the live DB, all four sources
// (personal / group / Duo / Moments) flipping 0 -> 1 in one
// transaction.
//
// What was missing is the nudge: nothing told an ALREADY-LOADED feed to ask
// again. everyone_feed_screen re-queries only in initState or via
// RefreshIndicator, so a user who changed a circle from a profile sheet kept
// staring at the page fetched before the change until they pulled down.
//
// Deliberately a counter, not a payload. The feed refetches from the server
// rather than patching its own list from a diff, so the RLS gate stays the
// single source of truth about who may see what — a client-side patch would
// be a second, weaker copy of that rule.
// ---------------------------------------------------------------------------

final feedRefreshSignal = ValueNotifier<int>(0);

/// Call after any change that alters feed VISIBILITY (not merely content).
/// Today that is circle membership (CircleService add/remove/setMembership):
/// being put in — or taken out of — someone's circle changes which of
/// their posts the server returns.
void signalFeedRefresh() => feedRefreshSignal.value++;
