-- Per-slot cooldown gate + slot-addressed pin RPCs.

CREATE OR REPLACE FUNCTION public.fmt_cooldown_remaining(p_until timestamptz)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_until IS NULL OR p_until <= now() THEN 'now'
    WHEN EXTRACT(epoch FROM p_until - now()) >= 86400
      THEN floor(EXTRACT(epoch FROM p_until - now()) / 86400)::int || 'd '
        || floor((EXTRACT(epoch FROM p_until - now())::int % 86400) / 3600)::int || 'h'
    WHEN EXTRACT(epoch FROM p_until - now()) >= 3600
      THEN floor(EXTRACT(epoch FROM p_until - now()) / 3600)::int || 'h '
        || floor((EXTRACT(epoch FROM p_until - now())::int % 3600) / 60)::int || 'm'
    ELSE greatest(1, ceil(EXTRACT(epoch FROM p_until - now()) / 60)::int) || 'm'
  END;
$$;

-- When slot p_slot of p_user unlocks. NULL = never used / already free.
-- NOTE: written so a missing pin_slots row yields NULL rather than a NULL
-- boolean that a caller might then negate -- the exact three-valued-logic
-- shape that produced the earlier is_admin auth bypass. Every caller below
-- tests `IS NOT NULL AND > now()`, never `NOT (...)`.
CREATE OR REPLACE FUNCTION public.pin_slot_unlocks_at(p_user uuid, p_slot smallint)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT s.last_changed_at + public.pin_cooldown()
  FROM pin_slots s
  WHERE s.user_id = p_user AND s.slot = p_slot AND s.last_changed_at IS NOT NULL;
$$;

-- The single gate every pin mutation goes through. p_target NULL = clear.
CREATE OR REPLACE FUNCTION public.apply_pin_slot(p_me uuid, p_slot smallint, p_target uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_unlocks timestamptz;
  v_current uuid;
BEGIN
  IF p_slot IS NULL OR p_slot < 1 OR p_slot > 5 THEN
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

  -- Start the clock. Fires for a CLEAR as well as a swap: removing counts
  -- as a change, which is what closes the unpin-then-repin loophole.
  INSERT INTO pin_slots (user_id, slot, last_changed_at)
  VALUES (p_me, p_slot, now())
  ON CONFLICT (user_id, slot) DO UPDATE SET last_changed_at = now();

  RETURN p_target IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_pin_slot(p_slot smallint, p_pinned_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'no matching users row for auth.uid()'; END IF;
  RETURN public.apply_pin_slot(v_me, p_slot, p_pinned_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_pin_slot(p_slot smallint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'no matching users row for auth.uid()'; END IF;
  PERFORM public.apply_pin_slot(v_me, p_slot, NULL);
  RETURN true;
END;
$$;

-- All 5 slots, always -- empty/locked ones included, so the UI can render
-- the countdown without inventing placeholder rows client-side.
CREATE OR REPLACE FUNCTION public.my_pin_slots()
RETURNS TABLE(
  slot smallint, pinned_user_id uuid, name text, profile_photo_url text,
  pinned_at timestamptz, unlocks_at timestamptz, locked boolean, ever_used boolean
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH me AS (SELECT id FROM users WHERE auth_id = auth.uid()),
  slots AS (SELECT generate_series(1,5)::smallint AS slot)
  SELECT
    s.slot,
    pp.pinned_user_id,
    u.name,
    u.profile_photo_url,
    (pp.created_at AT TIME ZONE 'UTC')::timestamptz,
    ps.last_changed_at + public.pin_cooldown(),
    COALESCE(ps.last_changed_at + public.pin_cooldown() > now(), false),
    (ps.last_changed_at IS NOT NULL)
  FROM slots s
  CROSS JOIN me
  LEFT JOIN pinned_people pp ON pp.user_id = me.id AND pp.slot = s.slot
  LEFT JOIN users u          ON u.id = pp.pinned_user_id
  LEFT JOIN pin_slots ps     ON ps.user_id = me.id AND ps.slot = s.slot
  ORDER BY s.slot;
$$;

GRANT EXECUTE ON FUNCTION public.set_pin_slot(smallint, uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_pin_slot(smallint)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_pin_slots()                TO authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_pin_slot(uuid, smallint, uuid) FROM anon, authenticated;
