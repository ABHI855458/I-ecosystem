-- ============================================================================
-- Us Album posts get a real caption + a real audience, matching what a
-- normal personal post already gets (Friends baseline + optional Communities
-- / Circles), via the new UsAlbumPostScreen / UsAlbumService.addPhotoWithAudience.
--
-- Three independent pieces, bundled because they all sit on the exact code
-- path that new flow exercises:
--
--   1. us_album_photos.caption — nowhere to read a real caption from before;
--      the mirrored post's `content` was always left null.
--
--   2. profile_posts_for_viewer() only ever matched p.user_id = p_profile —
--      a Us post never showed up on the TAGGED PARTNER's own profile Posts
--      tab, regardless of visibility, because the function never looked at
--      partner_user_id at all. This is what makes "visit the other person's
--      profile, see the Us Album photo in their Posts tab" actually work.
--
--   3. A one-off reset of every EXISTING 'mutual' us_album_photos row back to
--      'private', per explicit instruction ("for the older us album posts
--      clear them all") — those photos were shared with no caption and no
--      real audience choice (the old addPhoto() hardcoded 'mutual' with
--      neither), so under the new model they have no audience data to fall
--      back on. The existing sync trigger's own ELSE branch takes down each
--      one's mirrored post as a side effect of this UPDATE — nothing here
--      re-implements that.
--
-- NOTE: can_view_post() and friends_feed() need NO changes — read in full
-- (20260919000000_circles_private_audiences.sql, 20260907170000_us_post_visibility.sql)
-- and confirmed they already treat posts.partner_user_id as a full co-author
-- for the 'friends' visibility branch, and already support 'community' and
-- 'circle' post_audiences rows. Community/circle audience wiring for a Us
-- Album post is application-level (UsAlbumService inserts post_audiences
-- rows against the mirrored post id) — no new RLS needed.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused
-- — same convention as every other migration in this feature, e.g.
-- 20260907160000/20260907240000's own note).
-- ============================================================================

-- ── 1. Caption column, copied onto the mirrored post at publish time ───────

ALTER TABLE public.us_album_photos ADD COLUMN IF NOT EXISTS caption TEXT;

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
    -- Soft delete, not a hard one: comments and reactions people left on the
    -- post stay addressable, and every feed already filters deleted_at.
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = OLD.id AND deleted_at IS NULL;
    RETURN OLD;
  END IF;

  SELECT * INTO v_album FROM public.us_albums WHERE id = NEW.album_id;
  IF v_album.id IS NULL THEN
    RETURN NEW;
  END IF;

  -- The other member of the album is the co-author.
  v_partner := CASE WHEN v_album.user_a = NEW.uploaded_by
                    THEN v_album.user_b ELSE v_album.user_a END;

  -- Only ACCEPTED albums reach the feed. A pending invite is not yet a
  -- shared thing, and publishing it to the other person's friends before
  -- they have accepted would be exactly wrong.
  IF NEW.visibility = 'mutual' AND v_album.status = 'accepted' THEN
    INSERT INTO public.posts (
      user_id, partner_user_id, us_album_id, us_album_photo_id,
      image_url, content, visibility, post_type, created_at
    )
    VALUES (
      NEW.uploaded_by, v_partner, NEW.album_id, NEW.id,
      NEW.photo_url, NEW.caption, 'friends', 'us', NEW.created_at
    )
    ON CONFLICT (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL
    DO UPDATE SET image_url = EXCLUDED.image_url,
                  content   = EXCLUDED.content,
                  deleted_at = NULL;
  ELSE
    -- Flipped back to private (or the album is not accepted yet): take the
    -- post down without destroying it, so flipping to mutual again restores
    -- the same row rather than orphaning its comments.
    UPDATE public.posts SET deleted_at = now()
     WHERE us_album_photo_id = NEW.id AND deleted_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_us_album_post ON public.us_album_photos;
CREATE TRIGGER trg_sync_us_album_post
  AFTER INSERT OR UPDATE OF visibility, photo_url, caption OR DELETE
  ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.sync_us_album_post();

-- ── 2. profile_posts_for_viewer — also surface posts where the profile ─────
-- being viewed is the PARTNER, not just the uploader. Every other clause is
-- byte-for-byte unchanged from 20260922030000_profile_posts_post_audiences.sql.

CREATE OR REPLACE FUNCTION public.profile_posts_for_viewer(p_profile uuid)
RETURNS TABLE(id uuid, user_id uuid, content text, image_url text, photo_urls text[], photo_url_secondary text, inset_on_right boolean, visibility text, community_id uuid, community_name text, prompt text, post_type text, moment_color text, partner_user_id uuid, aspect_ratio text, photo_fit text, music_title text, music_artist text, music_url text, created_at timestamp with time zone)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_state text; v_auth uuid := auth.uid();
BEGIN
  v_state := public.profile_access_state(p_profile);

  IF v_state = 'locked' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.id, p.user_id, p.content, p.image_url, p.photo_urls,
         p.photo_url_secondary, COALESCE(p.inset_on_right, true),
         p.visibility,
         COALESCE(p.community_id, pa.community_id),
         COALESCE(c.name, ca.name),
         p.prompt, p.post_type, p.moment_color, p.partner_user_id,
         p.aspect_ratio, p.photo_fit,
         p.music_title, p.music_artist, p.music_url,
         (p.created_at AT TIME ZONE 'UTC')::timestamptz
  FROM public.posts p
  LEFT JOIN public.communities c ON c.id = p.community_id
  LEFT JOIN LATERAL (
    SELECT pa2.community_id FROM public.post_audiences pa2
     WHERE pa2.post_id = p.id AND pa2.audience_kind = 'community'
     LIMIT 1
  ) pa ON true
  LEFT JOIN public.communities ca ON ca.id = pa.community_id
  WHERE (p.user_id = p_profile OR p.partner_user_id = p_profile)
    AND p.deleted_at IS NULL
    AND p.visibility IN ('everyone','friends')
    AND p.post_type IS DISTINCT FROM 'moment'
    AND p.post_type IS DISTINCT FROM 'memory'
    AND (
      v_state IN ('self','friend')
      OR (
        v_state = 'community'
        AND COALESCE(p.community_id, pa.community_id) IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM public.community_members cm
           WHERE cm.community_id = COALESCE(p.community_id, pa.community_id)
             AND cm.user_id = v_auth
        )
      )
    )
  ORDER BY p.created_at DESC;
END;
$function$;

-- ── 3. Reset every existing 'mutual' photo back to 'private' ───────────────
-- Per explicit instruction. The trigger above takes down each one's mirrored
-- post automatically as a side effect of this UPDATE.
UPDATE public.us_album_photos SET visibility = 'private' WHERE visibility = 'mutual';
