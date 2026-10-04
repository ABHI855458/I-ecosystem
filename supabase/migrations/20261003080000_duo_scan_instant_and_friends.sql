-- ============================================================================
-- Duo: scanning connects instantly, accepting makes you friends, and the
-- partner hears about a post straight away (explicit requests, 2026-10-03).
--
-- 1. push_allowed(): 'duo_post' and 'group_message' now push IMMEDIATELY,
--    like 'ping_answered' already did, instead of waiting for the next
--    non-quiet window. Both are one person speaking to another — "the other
--    person shall be notified fast".
--
-- 2. duo_connect_by_scan(): a QR scan is both halves of the handshake at
--    once — the two phones are in the same room — so it creates the album
--    ALREADY accepted, with no invite to confirm ("when the QR is scanned
--    no need of accepting the duo request"). A request SENT from the app
--    keeps its accept flow untouched. Also friends them both ways.
--    Re-scanning an existing pending invite accepts it, whichever side
--    created it.
--
-- 3. trg_duo_accept_friends: accepting a Duo request through the NORMAL
--    flow also puts the two in each other's Friends circle ("accepting the
--    duo request will also add them to their friends list"). A trigger, so
--    it holds for every accept path — the sheet, a notification action, or
--    the scan above.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.push_allowed(p_tier text, p_type text, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- Person-to-person, always now: a ping answered, a liked reply, your
    -- Duo posting, somebody talking in a group chat.
    WHEN p_type IN ('ping_answered', 'ping_reply_liked', 'duo_post', 'group_message') THEN TRUE
    WHEN p_tier = 'major'    THEN w <> 'quiet'
    WHEN p_tier = 'standard' THEN w IN ('wake_digest','pre_class','snack_peak','lunch_peak','day_end','evening','last_call')
    ELSE                          w IN ('wake_digest','snack_peak','lunch_peak')
  END
  FROM (SELECT public.notification_window(p_at) AS w) s;
$function$;

-- ── Friends on accept, for every accept path ──────────────────────────────

CREATE OR REPLACE FUNCTION public.duo_accept_friends()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status <> 'accepted' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'accepted' THEN RETURN NEW; END IF;
  IF NEW.user_a IS NULL OR NEW.user_b IS NULL OR NEW.user_a = NEW.user_b THEN
    RETURN NEW;
  END IF;

  PERFORM public.seed_default_circles(NEW.user_a);
  PERFORM public.seed_default_circles(NEW.user_b);

  INSERT INTO public.circle_members (circle_id, member_id)
  SELECT c.id, x.member
    FROM (VALUES (NEW.user_a, NEW.user_b), (NEW.user_b, NEW.user_a))
           AS x(owner, member)
    JOIN public.circles c ON c.creator_id = x.owner AND c.kind = 'friends'
  ON CONFLICT (circle_id, member_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_duo_accept_friends ON public.us_albums;
CREATE TRIGGER trg_duo_accept_friends
  AFTER INSERT OR UPDATE OF status ON public.us_albums
  FOR EACH ROW EXECUTE FUNCTION public.duo_accept_friends();

REVOKE ALL ON FUNCTION public.duo_accept_friends() FROM PUBLIC, anon, authenticated;

-- ── A scan connects outright ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.duo_connect_by_scan(p_other uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me uuid := public.current_user_id();
  v_a uuid;
  v_b uuid;
  v_id uuid;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_other IS NULL OR p_other = v_me THEN
    RAISE EXCEPTION 'Cannot Duo with yourself.';
  END IF;
  IF public.is_blocked_user(auth.uid(), p_other) THEN
    RAISE EXCEPTION 'Cannot Duo with this user.';
  END IF;

  -- The pair is stored in a fixed order so one pair can only have one row.
  v_a := LEAST(v_me, p_other);
  v_b := GREATEST(v_me, p_other);

  SELECT id INTO v_id FROM public.us_albums
   WHERE user_a = v_a AND user_b = v_b
   ORDER BY created_at DESC LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.us_albums (user_a, user_b, created_by, status, responded_at)
    VALUES (v_a, v_b, v_me, 'accepted', now())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.us_albums
       SET status = 'accepted',
           responded_at = COALESCE(responded_at, now()),
           delete_requested_by = NULL,
           delete_requested_at = NULL
     WHERE id = v_id AND status <> 'accepted';
  END IF;

  -- Scanning someone in person is the friendship too.
  PERFORM public.seed_default_circles(v_me);
  PERFORM public.seed_default_circles(p_other);
  INSERT INTO public.circle_members (circle_id, member_id)
  SELECT c.id, x.member
    FROM (VALUES (v_me, p_other), (p_other, v_me)) AS x(owner, member)
    JOIN public.circles c ON c.creator_id = x.owner AND c.kind = 'friends'
  ON CONFLICT (circle_id, member_id) DO NOTHING;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.duo_connect_by_scan(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duo_connect_by_scan(uuid) TO authenticated;

COMMIT;
