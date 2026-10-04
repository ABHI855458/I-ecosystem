-- ============================================================================
-- Us Album photos become real posts in the Friends feed.
--
-- WHAT THIS SOLVES: an Us Album lived only on the two profiles. The ask is
-- that a mutual photo also appears in the Friends feed of BOTH people's
-- friends, as a proper post — with ping, RealMoji, comments and the "..."
-- menu working exactly as they do on a personal post, and the header showing
-- both people (fused avatars, both names).
--
-- WHY A `posts` ROW rather than rendering us_album_photos in the feed
-- directly: every one of those features is keyed on posts.id. Comments,
-- realmoji reactions, reports, view counts and the feed queries all join
-- through it. Surfacing the photo without a post row would mean
-- re-implementing all of them against a second id space; giving it a post row
-- makes them work with no changes at all.
--
-- The post row is maintained BY A TRIGGER, not by the app. Two clients (the
-- uploader's and the partner's) can both toggle a photo's visibility, and a
-- photo can be deleted while an app is offline — keeping the two tables in
-- step from Dart would drift. The trigger makes "a mutual photo has exactly
-- one live post" an invariant of the database.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

-- ── 1. Columns ──────────────────────────────────────────────────────────────

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS us_album_id uuid
    REFERENCES public.us_albums(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS us_album_photo_id uuid
    REFERENCES public.us_album_photos(id) ON DELETE CASCADE,
  -- The SECOND author. A normal post leaves this null.
  ADD COLUMN IF NOT EXISTS partner_user_id uuid
    REFERENCES public.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.posts.partner_user_id IS
  'Second author of a shared (Us Album) post. Treated as a co-author '
  'everywhere: can_view_post admits their friends, friends_feed serves it to '
  'them, and a ping on the post goes to both. Null on an ordinary post.';

-- One post per photo. Also what lets the trigger find the row to update.
CREATE UNIQUE INDEX IF NOT EXISTS posts_us_album_photo_uniq
  ON public.posts (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS posts_partner_idx
  ON public.posts (partner_user_id) WHERE partner_user_id IS NOT NULL;

-- ── 2. Keep posts in step with us_album_photos ──────────────────────────────
-- SECURITY DEFINER: the trigger writes a `posts` row on behalf of whichever
-- album member acted, and posts' own INSERT policy is scoped to user_id =
-- self. The row it writes is fully derived from the photo it fires for —
-- nothing here takes a caller-supplied value — so this cannot be used to
-- author a post as somebody else.

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
      image_url, visibility, post_type, created_at
    )
    VALUES (
      NEW.uploaded_by, v_partner, NEW.album_id, NEW.id,
      NEW.photo_url, 'friends', 'us', NEW.created_at
    )
    ON CONFLICT (us_album_photo_id) WHERE us_album_photo_id IS NOT NULL
    DO UPDATE SET image_url = EXCLUDED.image_url, deleted_at = NULL;
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
  AFTER INSERT OR UPDATE OF visibility, photo_url OR DELETE
  ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.sync_us_album_post();

-- When an album is accepted, publish the mutual photos already in it.
CREATE OR REPLACE FUNCTION public.sync_us_album_on_accept()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN
    -- Re-fire the photo trigger for every mutual photo by touching them.
    UPDATE public.us_album_photos SET visibility = visibility
     WHERE album_id = NEW.id AND visibility = 'mutual';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_us_album_on_accept ON public.us_albums;
CREATE TRIGGER trg_sync_us_album_on_accept
  AFTER UPDATE OF status ON public.us_albums
  FOR EACH ROW EXECUTE FUNCTION public.sync_us_album_on_accept();
