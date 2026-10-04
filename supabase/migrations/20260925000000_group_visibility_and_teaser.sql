-- "Blurred Group Teaser" feature, DB layer.
--
-- 1. groups.visibility — new column. Defaults to 'private' so every
--    EXISTING group keeps exactly its current behaviour (no self-join
--    mechanism exists today at all — every group_members row so far was
--    added by an existing member or admin, confirmed live: there was no
--    self-insert policy). 'public' is an explicit, new choice a creator
--    makes going forward; it is never silently applied to existing data.
--
-- 2. Self-join, public groups only. There was no self-join path in this
--    schema before this migration.
--
-- 3. member_add_members tightened: an ordinary (non-admin) member could
--    add anyone to ANY group, public or private, before this. Per the
--    explicit spec ("private[:] there is no option, the admin only shall
--    add the members"), that casual add-a-friend path now only applies to
--    PUBLIC groups; a private group can only ever gain a member via
--    admin_add_members or the new self-join policy (which itself is
--    public-only), so private really means admin-gatekept end to end.
--
-- 4. group_posts_teaser_for_community() — the actual teaser mechanic.
--    Returns group posts from a community's groups that the caller can't
--    already see in full (not a member, not audience-admitted), with
--    photo_urls TRUNCATED server-side to just the cover (index 0) and a
--    hidden_count instead of the real remaining URLs. This is the
--    security-relevant part: the client is never handed the locked
--    photos and asked to hide them — the row simply never contains them,
--    same discipline as every anonymity fix earlier this project.

ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'private'
    CHECK (visibility IN ('public', 'private'));

CREATE POLICY self_join_public_group ON public.group_members
  FOR INSERT
  WITH CHECK (
    role = 'member'
    AND user_id IN (SELECT id FROM public.users WHERE auth_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.groups g
       WHERE g.id = group_members.group_id AND g.visibility = 'public'
    )
  );

DROP POLICY IF EXISTS member_add_members ON public.group_members;
CREATE POLICY member_add_members ON public.group_members
  FOR INSERT
  WITH CHECK (
    role = 'member'
    AND is_group_member(group_id, (SELECT users.id FROM users WHERE users.auth_id = auth.uid()))
    AND EXISTS (
      SELECT 1 FROM public.groups g
       WHERE g.id = group_members.group_id AND g.visibility = 'public'
    )
  );

CREATE OR REPLACE FUNCTION public.group_posts_teaser_for_community(p_community_id uuid)
RETURNS TABLE(
  id uuid,
  group_id uuid,
  group_name text,
  group_icon_url text,
  cover_photo_url text,
  hidden_photo_count integer,
  caption text,
  created_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    gp.id, gp.group_id, g.name, g.icon_url,
    gp.photo_urls[1] AS cover_photo_url,
    GREATEST(cardinality(gp.photo_urls) - 1, 0) AS hidden_photo_count,
    gp.caption, gp.created_at
  FROM public.group_posts gp
  JOIN public.groups g ON g.id = gp.group_id
  WHERE gp.deleted_at IS NULL
    AND g.community_id = p_community_id
    -- Only posts with something ACTUALLY behind the teaser — a one-photo
    -- post has nothing to blur, so it stays exclusively on the existing
    -- full-visibility paths (member / shared-audience) instead of ever
    -- appearing here.
    AND cardinality(gp.photo_urls) > 1
    -- The viewer must be a real member of this community — the teaser
    -- widens discovery to "your campus", not to literally everyone with
    -- an account.
    AND public.is_community_member(p_community_id, auth.uid())
    -- Exclude anyone who already has full access through an existing
    -- path: a member sees it in full via group_posts_select already, and
    -- someone in the post's own shared audience sees it in full via
    -- group_posts_select_shared_audience. The teaser is additive, not a
    -- second way to see something you can already see completely.
    AND NOT EXISTS (
      SELECT 1 FROM public.group_members gm
       WHERE gm.group_id = gp.group_id
         AND gm.user_id = (SELECT id FROM public.users WHERE auth_id = auth.uid())
    )
    AND NOT public.group_post_audience_admits(gp.id, gp.user_id)
  ORDER BY gp.created_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.group_posts_teaser_for_community(uuid) TO authenticated;
