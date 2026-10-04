# Tracked follow-ups

Filed here (no issue tracker currently connected — GitHub CLI unauthenticated,
no Linear/Jira reference in this repo). Move to a real tracker once one's
wired up; keep this file until then.

---

## TICKET 1 — Reaction-fetch path 22P02 on local-only demo posts (LIVE BUG, prioritize)

**Status:** Open. Not fixed inline — flagged during feed-rules work
(2026-08-27) and deliberately left for separate triage.

**Severity:** Live/active, not cosmetic. Happens on every load of the
Friends feed while `DemoContent`'s local-only posts are present (i.e. on
essentially every dev/demo run, and for any real user session where the
local demo seed hasn't been cleared).

**What's happening:**
`PostReactions.loadReactionSummary` (`lib/screens/feed/widgets/post_card_shared.dart`)
calls `ReactionService.instance.fetchSummary(postId)` for every card in the
Friends feed, including cards backed by `DemoContent`'s local-only
`LocalPost` objects (ids like `demo-post-1` through `demo-post-8`, see
`lib/services/demo_content.dart`). Those ids are never real Supabase rows —
`DemoContent`'s own doc says "Never touches Supabase." The reaction fetch
sends `demo-post-1` etc. straight into a Postgrest query expecting a UUID,
which throws:

```
PostgrestException(message: invalid input syntax for type uuid: "demo-post-1", code: 22P02, ...)
```

Confirmed via runtime logs (2026-08-27 verification pass) — every `22P02`
seen in that session traced to this exact call path, not to the Anon feed
(which was the thing actually under test and had zero failures).

**Fix:**
The comment/count path already has the right pattern —
`post_card_shared.dart:2220`:

```dart
bool _isLocalDemoPostId(String? postId) => postId != null && postId.startsWith('demo-post-');
```

Mirror that guard into `PostReactions.loadReactionSummary` (and check
`loadMyRealmojiReaction` / any other per-post Supabase call in the same
mixin — the repro session saw the same exception shape from
`RealmojiService.myReaction` too, so this likely isn't the only call site
missing the guard). Skip the network call outright for a local-demo id and
either show a neutral/zero reaction state or skip the fetch's own loading
UI, rather than firing a request guaranteed to fail.

**Why not fixed inline:** raised as a review finding while verifying an
unrelated feed-rules change; explicitly deferred to its own pass rather than
scope-creeping into that branch.

---

## TICKET 2 — `posts_feed` has no engagement counts → N+1 on the Anon feed (needs privacy review, not just a code fix)

**Status:** Open, documented as a TODO in
`supabase/migrations/2026-08-25_feed_rules.sql` and cross-referenced in
`lib/features/home/anon_feed_v2/anon_feed_models.dart`. This ticket exists
so the constraint below isn't lost if that migration file gets archived —
**do not let anyone pick this up and just add the columns without doing the
privacy review.**

**Problem, concretely:**
`posts_feed` (the view the Anon feed queries) returns no reaction or
comment count. `AnonFeedPost.fromRow` therefore leaves those counts `null`
("unknown," not "zero" — a real `0` would falsely read as "nobody
reacted"). The Anon feed screen backfills them itself, one round-trip per
post per page (`_AnonFeedScreenV2State._hydrateCounts`,
`ReactionService.fetchSummary` + `CommentService.fetchCount`), and shows a
shimmer skeleton (`_CountOrSkeleton`) until each resolves.

**Query count, explicitly:** 1 query for the page + up to 2 queries per
post in it. At the current page size of 20, that's **up to 41 queries to
render one page** of the Anon feed.

**The constraint that makes this not a quick fix:**
`posts_feed` is a **security-sensitive view** — it masks `user_id` on
anonymous posts (see `supabase/schema.sql`), and every anon-identity
protection in this app leans on that masking holding. Adding
`reaction_count`/`comment_count` columns means the count itself has to
respect the same RLS the base `reactions` / `post_realmoji_reactions` /
`comments` tables enforce, or the count becomes a side-channel leak (e.g. a
nonzero count on a post ID the requester shouldn't even be able to confirm
exists). **Whoever implements this must explicitly re-review the anon-leak
surface of `posts_feed` as part of the change, not just bolt on a `LEFT
JOIN` and ship it.**

**Fix (once reviewed):**
Add `reaction_count`/`comment_count` to the `posts_feed` view definition
(correlated subqueries or a grouped `LEFT JOIN` over the three reaction/
comment tables, RLS-safe). Then `AnonFeedPost.fromRow` reads them directly,
and `_hydrateCounts` + `_CountOrSkeleton` can both be deleted outright.

**Why not fixed inline:** deliberately scoped out of the 2026-08-25
feed-rules migration (index-only) specifically so this didn't ride along
without its own review — see that migration file's own TODO block for the
original reasoning.

---

## TICKET 3 — Us-album 'mutual' visibility needs a SECURITY DEFINER helper, not plain `friendships` SELECT

**Status:** Open, flagged during Phase 2 (friendships table) design review
(2026-08-27), before Phase 3 (Us albums) starts.

**What's coming:** Us albums (Phase 3) will have a `'mutual'` photo
visibility state — visible to the album's two owners AND any viewer who is
a mutual friend of BOTH of them (friends with A *and* friends with B).

**The constraint:** `friendships`' own RLS (`supabase/migrations/20260827000000_friendships.sql`)
only lets a user SELECT rows they're a party to (`friendships_select_own` —
`auth.uid()` must match either `requester_id` or `addressee_id`'s
`auth_id`). That's correct and intentional for the friendships table
itself — nobody should be able to list a stranger's full friend list. But
it means a plain client-side query CANNOT compute "is viewer V a mutual
friend of both A and B" — V has no RLS-granted visibility into A's or B's
friendship rows with third parties.

**Fix (once Phase 3 is underway):** A `SECURITY DEFINER` function (same
pattern as `2026-08-22_three_tier_roles.sql`'s moderator-role helpers) that
takes `(viewer_id, owner_a_id, owner_b_id)` and returns whether the
mutual-friend condition holds, computed server-side with elevated
privileges bypassing the per-row RLS restriction, without ever exposing raw
friendship rows to the client. **Do not ship 'mutual' visibility gated by
a plain table query** — it will either always return empty (correct RLS,
wrong tool) or require weakening `friendships` SELECT RLS app-wide to make
the client-side query work, which would leak everyone's full friend list to
everyone. Whichever engineer picks this up should design the function
signature against the actual `us_albums`/`us_album_photos` schema once
that's finalized, not before.

**Why not fixed inline:** friendships (Phase 2) is a prerequisite for this,
not the same piece of work — flagged now, during Phase 2, specifically so
it isn't rediscovered the hard way when Phase 3 starts.

---

## TICKET 4 — No cooldown on friend re-requesting: UX/safety call, not just a technical detail (revisit before launch)

**Status:** Open, deliberately deferred. Flagged during Phase 2 design
review (2026-08-27) as a product decision to make before launch, not
during this build.

**Current design:** `friendships` has no `'declined'` state — declining a
pending request (or unfriending an accepted one) just DELETES the row.
"No relationship" is "no row." This means either side can immediately
re-request right after being declined, with zero cooldown, zero rate
limit, and zero record that a decline ever happened.

**Why this is a real consideration, not a nitpick:** this is a small,
close-knit campus app — the person on the other end of an unwanted repeat
friend request is someone the requester likely sees in person regularly.
Unlimited immediate re-requesting after a decline is a harassment vector in
a way it might not be on a large anonymous platform. This is explicitly
**not** the same category as TICKET 1/2/3's technical fixes — it's a
product/safety judgment call about this specific user base.

**Options to weigh before launch (not decided yet):**
- Leave as-is (simplest; relies on addressee just declining repeatedly).
- A cooldown window (e.g. can't re-request the same person for N days
  after a decline) — needs a new column (e.g. `last_declined_at`, kept even
  though the row itself gets deleted — likely a small separate table or a
  soft-delete instead of a hard DELETE on decline, which is a real schema
  change from what's live now).
- A cap on requests-per-day sent by one user, independent of any single
  target (blunter, catches spam-adds generally, not just repeat-target
  harassment).

**Why not fixed inline:** explicitly out of scope for the Phase 2 build —
flagged as a decision to revisit deliberately before launch, per direct
instruction, not something to design reactively mid-build.

---

## TICKET 5 — Every Storage bucket is public, undermining `us_album_photos.visibility = 'private'`'s own guarantee (LAUNCH BLOCKER for Us albums specifically)

**Status:** Open. Discovered during Phase 3 (Us albums) real-data wiring
(2026-08-29), while about to build the photo-upload path — flagged before
writing that code, not after.

**What's happening:** Every Supabase Storage bucket in this project
(`posts`, `profiles`, `personas`, `group-photos`, `group-icons`,
`bucket-photos`, `reaction-photos`, `Memories` — confirmed via direct query
against `storage.buckets`, all 8 existing buckets) is `public: true`. A
public bucket serves any object at its public URL to **anyone holding that
URL, with zero authentication** — this is a Supabase Storage primitive, not
a bug in this app's code. Table-level RLS (e.g. the `us_album_photos`
policies from `20260828000000_us_albums.sql`) only gates who can *query the
database row* — i.e. who the app will show the URL to. It does nothing to
protect the raw file once a URL is known by any means (shared, leaked,
guessed, cached, referrer-logged, etc.).

**Why this is specifically a problem for Us albums and not (as urgently) the
rest of the app:** every other bucket already has this same structural gap,
but none of them make an explicit, named, user-facing privacy promise the
way Us albums does — `visibility = 'private'` (the DEFAULT for every
photo) is a first-class product guarantee stated directly to users (the
🔒/🌐 toggle in the design). Shipping that on a fully public bucket makes a
"private" photo's real-world exposure **identical** to a "mutual" one the
instant its URL is known by any means outside the app's own RLS-gated
query path — the feature's central promise would be weaker than its own
name.

**Fix, in order of increasing effort:**
1. **Minimum (mitigation, not a fix):** use a long, random (UUID-based),
   non-guessable object path per photo — makes URL-guessing infeasible,
   but does nothing about a URL that leaks by any other means (a screenshot
   of dev tools, a copied share link, a referrer header, browser cache,
   etc.). This alone is NOT sufficient for a feature that explicitly
   promises "private."
2. **Real fix:** make the `us-albums` bucket (once created) `public: false`
   and serve photos via short-lived signed URLs
   (`createSignedUrl`/`createSignedUrls`), generated per-request only after
   the caller has already passed `us_album_photos`' own SELECT RLS. This is
   the standard Supabase pattern for actually-private storage and is a
   real client-side change (every read site needs to fetch a signed URL
   instead of using a stored public one, and signed URLs expire — caching/
   refresh logic needed), not a one-line config flip.

**Why not fixed inline:** discovered mid-build of Phase 3's photo-upload
path; fixing it properly (option 2) is bigger than "create a bucket" and
touches the read path too, not just upload — flagged for explicit review
rather than either (a) silently shipping "private" that isn't actually
private, or (b) silently scope-creeping Phase 3 into a signed-URL
refactor without asking first.

---

## TICKET 5 — Phase A+B ready to execute (written 2026-09-20)

**Status: migration + service layer written, NOT yet run. Render sites not yet converted.**

Verified exploitable before writing this: an unauthenticated GET (no apikey,
no JWT, no cookies) against a `visibility='private'` Us-album photo returned
`HTTP 200, 390KB, image/jpeg`. For ping photos the same hole defeats
hold-to-reveal entirely — the raw URL serves the photo whether or not the
viewer ever held to reveal.

### Already written
- `supabase/migrations/20260921000000_ticket5_private_buckets_phase_ab.sql`
  — storage SELECT policies, bucket flip, stored-URL rewrite, plus VERIFY
  queries and an ORDER OF OPERATIONS note. Run in the SQL Editor.
- `StorageService.signedUrlFor()` / `signedUsAlbumPhotoUrl()` /
  `signedPingPhotoUrl()` — safe to ship BEFORE the SQL (passes absolute
  URLs through unchanged, signs bare paths).
- `clearSignedUrlCache()` wired into `SupabaseService.signOutAndResetCaches`.

### Still to do in the fresh session
1. Convert the render sites to resolve through the signed helpers. They
   currently feed a stored string straight into `CachedNetworkImage`:
   - `lib/features/ping/ping_page.dart` — approx. lines 2655, 3669, 4143,
     4258 (reply photo, wall thread photo, wall tile photo, wall selfie).
   - Us-album: `profile_v2_sections.dart`, `their_profile_screen.dart`,
     `my_profile_screen.dart`, `album_photo_viewer.dart`.
   These are async now, so each needs a FutureBuilder (or resolve-on-load
   into state) with the existing placeholder on null.
2. Run the migration, then its VERIFY queries (a)-(d).
3. **Real verification — a broken image is the expected failure mode.**
   Not "the migration ran without error": open the app and confirm
   Us-album photos and revealed ping replies actually render, and confirm
   the old public URL now returns 400/404 instead of 200.

### Deliberately out of scope
- Phase C (`posts`, `reaction-photos`) — parked for its own session.
- `profiles` / `group-icons` stay public. Avatars are shown broadly by
  design; making them private buys nothing and costs a signing round-trip
  per render.
