-- post_realmoji_reactions_select only lets a viewer read reaction rows on
-- an anonymous post if they're that post's AUTHOR — there is no branch
-- letting a REACTOR read back their own reaction row on someone ELSE's
-- anon post. Confirmed live: a non-author's insert succeeds (insert-own
-- policy is unaffected) but a subsequent select-your-own-row-back returns
-- zero rows. This is the same anon-RLS failure shape already fixed once
-- for comments_select (20260905020000_fix_comments_select.sql) — a write
-- that silently can never be read back by its own author, discovered only
-- via direct policy testing, not visible as an app error.
--
-- Concrete effect before this fix: RealmojiService.myReaction (read by
-- DailyPromptService... no — by the anon feed's _hydrateCounts) always
-- returned null for a reaction on someone else's anon post, so the
-- reacted-state pill never restored after a reload even though the
-- reaction was correctly saved and correctly counted in the aggregate
-- (anon_reaction_counts bypasses this restriction entirely, since that
-- view is owned by postgres and its own internal query isn't subject to
-- the querying role's RLS).
--
-- Additive PERMISSIVE policy — OR's onto the existing restrictive-author
-- rule rather than replacing it, so nothing already working narrows.
create policy post_realmoji_reactions_select_own on post_realmoji_reactions
  for select
  using (
    auth.uid() in (select users.auth_id from users where users.id = post_realmoji_reactions.user_id)
  );
