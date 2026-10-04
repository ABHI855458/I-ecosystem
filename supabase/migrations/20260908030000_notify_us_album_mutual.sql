-- ============================================================================
-- C2: when a Us-album photo is tagged mutual, the OTHER party (not the
-- uploader) gets notified. Persistence itself was already real
-- (us_album_photos is a normal table with real RLS-gated inserts/updates —
-- confirmed by reading UsAlbumService/us_albums migration); the gap was
-- only the notification, which — like every other notification in this
-- app — must be written by a SECURITY DEFINER trigger, not client code:
-- notifications has no INSERT policy for authenticated/anon at all (see
-- 20260907020000_notifications.sql), by design.
--
-- Fires on the private->mutual transition specifically (us_album_photos'
-- own visibility default is 'private'; 'mutual' is only ever reached via
-- an UPDATE — see UsAlbumService.setPhotoVisibility and
-- us_album_photos_update_own's RLS, which restricts this to the photo's
-- own uploader), mirroring notify_friend_accepted's AFTER UPDATE pattern.
--
-- Idempotent, safe to re-run.
-- ============================================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('reaction', 'ping', 'friend_request', 'friend_accepted', 'branch_view', 'us_album_mutual'));

CREATE OR REPLACE FUNCTION public.notify_us_album_mutual()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_recipient uuid;
  v_actor_name text;
BEGIN
  IF NOT (OLD.visibility <> 'mutual' AND NEW.visibility = 'mutual') THEN
    RETURN NEW;
  END IF;

  SELECT CASE WHEN user_a = NEW.uploaded_by THEN user_b ELSE user_a END
    INTO v_recipient
    FROM public.us_albums
    WHERE id = NEW.album_id;

  IF v_recipient IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(name, anon_name, 'someone') INTO v_actor_name
    FROM public.users WHERE id = NEW.uploaded_by;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, dedupe_key)
  VALUES (
    v_recipient, 'us_album_mutual', NEW.uploaded_by, 'standard',
    COALESCE(v_actor_name, 'someone') || ' added a photo to your Us album',
    NULL,
    'us_album_mutual:' || NEW.id::text
  )
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_us_album_mutual() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_us_album_mutual ON public.us_album_photos;
CREATE TRIGGER trg_notify_us_album_mutual
  AFTER UPDATE ON public.us_album_photos
  FOR EACH ROW EXECUTE FUNCTION public.notify_us_album_mutual();
