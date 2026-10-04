-- ============================================================================
-- group_card_post(): the post row a feed group card needs (caption, note,
-- place, taken_at, aspect ratio) for anyone the post is SHOWN to — including
-- a locked viewer, whom group_posts RLS hides the row from. Guarded by the
-- same group_post_feed_access() the feed uses, so it never widens access.
-- Lets the feed card be an exact copy of the group-profile card (note under
-- the photo, location in the footer) for locked posts too.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.group_card_post(p_group_post uuid)
RETURNS TABLE(id uuid, user_id uuid, caption text, note text, place text,
              taken_at timestamptz, created_at timestamptz, aspect_ratio text,
              photo_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT gp.id, gp.user_id, gp.caption, gp.note, gp.place,
         gp.taken_at, gp.created_at, gp.aspect_ratio, gp.photo_url
    FROM public.group_posts gp
   WHERE gp.id = p_group_post
     AND gp.deleted_at IS NULL
     AND public.group_post_feed_access(p_group_post) IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.group_card_post(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_card_post(uuid) TO authenticated;

COMMIT;
