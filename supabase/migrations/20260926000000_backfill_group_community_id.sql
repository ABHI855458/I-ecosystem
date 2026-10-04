-- Blurred Group Teaser (group_posts_teaser_for_community, migration
-- 20260925000000_group_visibility_and_teaser.sql) joins on
-- groups.community_id — but nothing ever set it. GroupService.createGroup
-- never included it in the insert, so every existing group has it NULL,
-- and the teaser function's `g.community_id = p_community_id` clause can
-- never match. Confirmed live: all 7 existing groups had community_id
-- NULL. The function itself has NO visibility check — the teaser was
-- always meant to apply to public and private groups alike (only the QR/
-- self-join path is public-only) — so this column was the whole gap.
--
-- First attempt at this backfill joined groups.created_by (users.id)
-- directly against community_members.user_id and updated zero rows —
-- community_members.user_id is actually the AUTH id (auth.uid()), not
-- users.id, confirmed live by inspecting a known account's rows. Bridging
-- through users.auth_id below.
--
-- One-time backfill: each group's community_id becomes its creator's
-- earliest-joined community (an assumption — most creators belong to
-- exactly one — not a real "primary community" model). A group whose
-- creator has no community membership at all is left NULL; the teaser
-- simply never applies to it, which is the correct, harmless outcome.
UPDATE public.groups g
   SET community_id = pick.community_id
  FROM (
    SELECT DISTINCT ON (u.id) u.id AS user_id, cm.community_id
      FROM public.users u
      JOIN public.community_members cm ON cm.user_id = u.auth_id
     ORDER BY u.id, cm.joined_at ASC
  ) pick
 WHERE g.community_id IS NULL
   AND g.created_by = pick.user_id;
