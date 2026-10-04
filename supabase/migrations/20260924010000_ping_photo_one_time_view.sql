-- PING PHOTO — one-time view, matching how a reply's photo already works.
--
-- Explicit request: a photo attached to the ORIGINAL ping should be a
-- Snapchat-style one-time reveal (open, timed countdown, closes), the same
-- treatment ping_replies photos already get via photoViewId/_photoView in
-- ping_page.dart. Before this, pings.photo_url just rendered as a plain,
-- always-visible, indefinitely-re-viewable thumbnail inline in the card —
-- confirmed live, no ephemeral/hold-to-reveal treatment at all.
--
-- A reply's one-time-ness comes for free: the whole row disappears from
-- REPLIES once ping_replies.viewed flips true, so there's nothing left to
-- re-open. The ORIGINAL ping's card can't disappear the same way (the
-- recipient still needs it to compose their reply), so its photo needs its
-- own durable "already opened" flag — this column — rather than borrowing
-- the row's own lifecycle.
ALTER TABLE public.pings
  ADD COLUMN IF NOT EXISTS photo_opened_at timestamp with time zone;

-- Only the RECEIVER may open (and thereby burn) the sender's attached photo
-- — matches pings_select/ping_replies_insert's own receiver-only trust
-- boundary. Idempotent: opening twice in the same request race still only
-- ever records the first timestamp.
CREATE OR REPLACE FUNCTION public.mark_ping_photo_opened(p_ping_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN RETURN; END IF;

  UPDATE public.pings
     SET photo_opened_at = now()
   WHERE id = p_ping_id
     AND receiver_id = v_me
     AND photo_url IS NOT NULL
     AND photo_opened_at IS NULL;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.mark_ping_photo_opened(uuid) TO authenticated;
