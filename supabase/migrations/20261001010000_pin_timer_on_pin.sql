-- ============================================================================
-- Pin timer starts when someone is PINNED, not when a slot is emptied
-- (explicit request: "if not pinned it shall stay open, and when pinned the
-- timer shall start"). Empty slots are always open; a pinned person is
-- locked in for pin_cooldown() (7 days), then can be swapped or unpinned.
-- Existing empty-but-locked slots open immediately.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.apply_pin_slot(p_me uuid, p_slot smallint, p_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_unlocks timestamptz;
  v_current uuid;
BEGIN
  IF p_slot IS NULL OR p_slot < 1 OR p_slot > 3 THEN
    RAISE EXCEPTION 'invalid pin slot';
  END IF;

  SELECT pinned_user_id INTO v_current
  FROM pinned_people WHERE user_id = p_me AND slot = p_slot;

  -- No-op: asking for the state the slot is already in never burns cooldown.
  IF v_current IS NOT DISTINCT FROM p_target THEN
    RETURN p_target IS NOT NULL;
  END IF;

  v_unlocks := public.pin_slot_unlocks_at(p_me, p_slot);
  IF v_unlocks IS NOT NULL AND v_unlocks > now() THEN
    RAISE EXCEPTION 'This pin slot unlocks in %.', public.fmt_cooldown_remaining(v_unlocks);
  END IF;

  IF p_target IS NOT NULL THEN
    IF p_target = p_me THEN
      RAISE EXCEPTION 'cannot pin yourself';
    END IF;
    IF NOT COALESCE(public.shares_community(p_me, p_target), false) THEN
      RAISE EXCEPTION 'can only pin someone in a shared community';
    END IF;
    IF EXISTS (SELECT 1 FROM pinned_people
               WHERE user_id = p_me AND pinned_user_id = p_target AND slot <> p_slot) THEN
      RAISE EXCEPTION 'that person is already pinned in another slot';
    END IF;
  END IF;

  DELETE FROM pinned_people WHERE user_id = p_me AND slot = p_slot;

  IF p_target IS NOT NULL THEN
    INSERT INTO pinned_people (user_id, pinned_user_id, slot)
    VALUES (p_me, p_target, p_slot);
  END IF;

  -- The clock starts when someone is PINNED (explicit request): an empty
  -- slot stays open, and a pinned person is locked in for pin_cooldown().
  -- Clearing (only possible once that runs out) leaves the slot open.
  IF p_target IS NOT NULL THEN
    INSERT INTO pin_slots (user_id, slot, last_changed_at)
    VALUES (p_me, p_slot, now())
    ON CONFLICT (user_id, slot) DO UPDATE SET last_changed_at = now();
  ELSE
    UPDATE pin_slots SET last_changed_at = NULL
     WHERE user_id = p_me AND slot = p_slot;
  END IF;

  RETURN p_target IS NOT NULL;
END;
$function$
;;

CREATE OR REPLACE FUNCTION public.pin_slot_unlocks_at(p_user uuid, p_slot smallint)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Only an OCCUPIED slot is ever locked; an empty one is always open.
  SELECT s.last_changed_at + public.pin_cooldown()
  FROM pin_slots s
  JOIN pinned_people pp ON pp.user_id = s.user_id AND pp.slot = s.slot
  WHERE s.user_id = p_user AND s.slot = p_slot AND s.last_changed_at IS NOT NULL;
$function$
;;

CREATE OR REPLACE FUNCTION public.my_pin_slots()
 RETURNS TABLE(slot smallint, pinned_user_id uuid, name text, profile_photo_url text, pinned_at timestamp with time zone, unlocks_at timestamp with time zone, locked boolean, ever_used boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH me AS (SELECT id FROM users WHERE auth_id = auth.uid()),
  slots AS (SELECT generate_series(1,3)::smallint AS slot)
  SELECT
    s.slot,
    pp.pinned_user_id,
    u.name,
    u.profile_photo_url,
    (pp.created_at AT TIME ZONE 'UTC')::timestamptz,
    CASE WHEN pp.pinned_user_id IS NOT NULL
         THEN ps.last_changed_at + public.pin_cooldown() END,
    COALESCE(pp.pinned_user_id IS NOT NULL
             AND ps.last_changed_at + public.pin_cooldown() > now(), false),
    (ps.last_changed_at IS NOT NULL)
  FROM slots s
  CROSS JOIN me
  LEFT JOIN pinned_people pp ON pp.user_id = me.id AND pp.slot = s.slot
  LEFT JOIN users u          ON u.id = pp.pinned_user_id
  LEFT JOIN pin_slots ps     ON ps.user_id = me.id AND ps.slot = s.slot
  ORDER BY s.slot;
$function$
;;

-- Empty slots that were locked under the old rule open now.
UPDATE pin_slots ps SET last_changed_at = NULL
 WHERE NOT EXISTS (SELECT 1 FROM pinned_people pp
                    WHERE pp.user_id = ps.user_id AND pp.slot = ps.slot);

COMMIT;
