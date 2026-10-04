-- ============================================================================
-- A shared (Us Album) post is visible to BOTH authors' friends.
--
-- posts.partner_user_id is a co-author, so every place that asks "is the
-- viewer allowed to see this / should this be in their feed" has to consider
-- them the same way it considers user_id. Without this the post reaches only
-- the uploader's friends, and the partner's friends — half the point — never
-- see it. It also would not appear in the PARTNER's own feed at all.
--
-- Both objects are rewritten whole (they are small) rather than patched, so
-- the file reads as the complete current definition.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_view_post(p_post_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_viewer_id  UUID;
  v_author_id  UUID;
  v_partner_id UUID;
  v_visibility TEXT;
BEGIN
  SELECT id INTO v_viewer_id FROM users WHERE auth_id = auth.uid();
  IF v_viewer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT user_id, partner_user_id, visibility
    INTO v_author_id, v_partner_id, v_visibility
    FROM posts WHERE id = p_post_id;
  IF v_author_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Either author sees their own.
  IF v_viewer_id = v_author_id OR v_viewer_id = v_partner_id THEN
    RETURN TRUE;
  END IF;

  IF v_visibility <> 'friends' THEN
    RETURN TRUE;
  END IF;

  -- Friend of EITHER author. The partner branch is what makes a shared post
  -- reach the second person's friends.
  IF EXISTS (
    SELECT 1 FROM friendships
    WHERE status = 'accepted'
      AND (
        (requester_id = v_author_id AND addressee_id = v_viewer_id) OR
        (requester_id = v_viewer_id AND addressee_id = v_author_id) OR
        (v_partner_id IS NOT NULL AND (
          (requester_id = v_partner_id AND addressee_id = v_viewer_id) OR
          (requester_id = v_viewer_id AND addressee_id = v_partner_id)))
      )
  ) THEN
    RETURN TRUE;
  END IF;

  IF EXISTS (
    SELECT 1 FROM post_audiences pa
    WHERE pa.post_id = p_post_id
      AND pa.audience_kind = 'community'
      AND is_community_member(pa.community_id, auth.uid())
  ) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$function$;

-- ── friends_feed ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.friends_feed(
  p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS SETOF posts
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with me as (select id from public.users where auth_id = auth.uid())
  select p.* from public.posts p
  where p.deleted_at is null
    and p.post_type is distinct from 'memory'
    and p.user_id <> (select id from me)
    -- Not mine as the CO-author either: a shared post is my own post when I
    -- am the partner, and this feed is other people's posts.
    and p.partner_user_id is distinct from (select id from me)
    and (
      exists (select 1 from public.friendships f
              where f.status = 'accepted'
                and ((f.requester_id = (select id from me) and f.addressee_id = p.user_id)
                  or (f.addressee_id = (select id from me) and f.requester_id = p.user_id)))
      or
      -- Friend of the co-author. This is the branch that puts a shared post
      -- into the second person's friends' feeds.
      (p.partner_user_id is not null and exists (
         select 1 from public.friendships f
          where f.status = 'accepted'
            and ((f.requester_id = (select id from me) and f.addressee_id = p.partner_user_id)
              or (f.addressee_id = (select id from me) and f.requester_id = p.partner_user_id))))
      or
      exists (select 1 from public.post_audiences pa
              join public.community_members cm on cm.community_id = pa.community_id
              where pa.post_id = p.id
                and pa.audience_kind = 'community'
                and cm.user_id = auth.uid())
    )
  order by p.created_at desc
  limit p_limit offset p_offset;
$function$;
