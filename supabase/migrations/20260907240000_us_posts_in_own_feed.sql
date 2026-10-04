-- ============================================================================
-- A shared (Us Album) post appears in BOTH co-authors' own feeds.
--
-- friends_feed excludes your own posts — that is right for an ordinary post
-- (the Friends feed is other people's) and wrong for a shared one. An Us
-- Album post is a joint artifact; both people should see it in their feed,
-- which is what "seen in both of theirs feed" asked for. Reported as
-- "i cannot see my us album posts in the feed": the author was excluded by
-- p.user_id <> me, and the partner by the partner_user_id guard added in
-- 20260907170000.
--
-- Ordinary posts stay excluded. The exemption is scoped to post_type = 'us',
-- so this does not turn the Friends feed into a mirror of your own profile.
--
-- Also fixes the timestamp: sync_us_album_post copied the PHOTO's created_at
-- onto the post, so publishing a photo uploaded days ago produced a post that
-- was born already outside the feed's 48h window — invisible to everyone the
-- moment it was created. The post is created when the photo becomes mutual,
-- so that is the moment it should be dated from. Re-publishing a photo that
-- was flipped private keeps its original date (ON CONFLICT does not touch
-- created_at), so this cannot be used to bump a post back to the top.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

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
    and (
      -- A shared post is exempt from the own-post exclusion: both
      -- co-authors see it in their own feed.
      p.post_type = 'us'
      or (p.user_id <> (select id from me)
          and p.partner_user_id is distinct from (select id from me))
    )
    and (
      -- Co-author of a shared post.
      (p.post_type = 'us' and (p.user_id = (select id from me)
                            or p.partner_user_id = (select id from me)))
      or
      exists (select 1 from public.friendships f
              where f.status = 'accepted'
                and ((f.requester_id = (select id from me) and f.addressee_id = p.user_id)
                  or (f.addressee_id = (select id from me) and f.requester_id = p.user_id)))
      or
      -- Friend of the co-author — puts a shared post into the second
      -- person's friends' feeds.
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

-- ── Date the post from publication, not from the photo's upload ─────────────
CREATE OR REPLACE FUNCTION public.sync_us_album_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_album   public.us_albums%ROWTYPE;
  v_partner UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = OLD.id AND deleted_at IS NULL;
    RETURN OLD;
  END IF;

  SELECT * INTO v_album FROM public.us_albums WHERE id = NEW.album_id;
  IF v_album.id IS NULL THEN
    RETURN NEW;
  END IF;

  v_partner := CASE WHEN v_album.user_a = NEW.uploaded_by
                    THEN v_album.user_b ELSE v_album.user_a END;

  IF NEW.visibility = 'mutual' AND v_album.status = 'accepted' THEN
    INSERT INTO public.posts (
      user_id, partner_user_id, us_album_id, us_album_photo_id,
      image_url, visibility, post_type, created_at
    )
    VALUES (
      NEW.uploaded_by, v_partner, NEW.album_id, NEW.id,
      NEW.photo_url, 'friends', 'us', now()
    )
    ON CONFLICT (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL
    DO UPDATE SET image_url = EXCLUDED.image_url, deleted_at = NULL;
  ELSE
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = NEW.id AND deleted_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

-- The three posts created by the backfill inherited their photo's upload
-- date (one of them 4 days old), so they were already outside the 48h feed
-- window before anyone could see them. Date them from when they were
-- actually published.
UPDATE public.posts
   SET created_at = now()
 WHERE post_type = 'us' AND deleted_at IS NULL
   AND created_at < now() - interval '12 hours';
