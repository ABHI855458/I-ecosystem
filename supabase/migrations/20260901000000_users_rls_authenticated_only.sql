-- Phase 0b of the users/profiles identity-reconciliation plan (see
-- /Users/abhishek/.claude/plans/before-building-the-audience-iterative-beacon.md).
-- Independent of the rest of that plan — ship on its own.
--
-- `users`'s three policies were granted to {public}, not {authenticated} — the
-- ONLY table in this schema with that grant (verified live: `profiles` and
-- `community_members` are both already {authenticated}). {public} in a
-- Postgres/PostgREST policy includes the anon role, so the anon API key could
-- read every row of `users` — including `email` and `name` — and could insert/
-- update rows too (auth.uid() is NULL for an anon request, so those two policies
-- were not exploitable the same way, but SELECT had no such guard: `USING (true)`
-- unconditionally allows it).
--
-- This does not change WHAT any policy allows for a signed-in user — only WHO
-- is even evaluated: anon requests are rejected before the policy body runs.

ALTER POLICY users_select     ON users TO authenticated;
ALTER POLICY users_insert_own ON users TO authenticated;
ALTER POLICY users_update_own ON users TO authenticated;
