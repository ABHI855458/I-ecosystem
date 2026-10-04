-- The three pre-existing entry points now delegate to apply_pin_slot().
-- Left in place rather than dropped because the app still calls them
-- (PostAuthorPinService.pinPerson / unpin / toggle), and because a second
-- un-gated write path into pinned_people IS the bypass -- the cooldown is
-- only real if every door goes through the same gate.

CREATE OR REPLACE FUNCTION public.pin_person(p_pinned_user_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
  v_slot smallint;
  v_soonest timestamptz;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'no matching users row for auth.uid()'; END IF;

  IF EXISTS (SELECT 1 FROM pinned_people WHERE user_id = v_me AND pinned_user_id = p_pinned_user_id) THEN
    RETURN (SELECT count(*)::int FROM pinned_people WHERE user_id = v_me);
  END IF;

  -- Lowest slot that is both empty AND off cooldown.
  SELECT s.slot::smallint INTO v_slot
  FROM generate_series(1,5) AS s(slot)
  LEFT JOIN pinned_people pp ON pp.user_id = v_me AND pp.slot = s.slot::smallint
  WHERE pp.pinned_user_id IS NULL
    AND COALESCE(public.pin_slot_unlocks_at(v_me, s.slot::smallint), now()) <= now()
  ORDER BY s.slot
  LIMIT 1;

  IF v_slot IS NULL THEN
    IF (SELECT count(*) FROM pinned_people WHERE user_id = v_me) >= 5 THEN
      RAISE EXCEPTION 'pin limit reached (5)';
    END IF;
    SELECT min(public.pin_slot_unlocks_at(v_me, s.slot::smallint)) INTO v_soonest
    FROM generate_series(1,5) AS s(slot)
    LEFT JOIN pinned_people pp ON pp.user_id = v_me AND pp.slot = s.slot::smallint
    WHERE pp.pinned_user_id IS NULL;
    RAISE EXCEPTION 'Your next free pin slot unlocks in %.', public.fmt_cooldown_remaining(v_soonest);
  END IF;

  PERFORM public.apply_pin_slot(v_me, v_slot, p_pinned_user_id);
  RETURN (SELECT count(*)::int FROM pinned_people WHERE user_id = v_me);
END;
$$;

CREATE OR REPLACE FUNCTION public.unpin_person(p_pinned_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
  v_slot smallint;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'no matching users row for auth.uid()'; END IF;

  SELECT slot INTO v_slot FROM pinned_people
  WHERE user_id = v_me AND pinned_user_id = p_pinned_user_id;

  IF v_slot IS NULL THEN RETURN false; END IF;

  PERFORM public.apply_pin_slot(v_me, v_slot, NULL);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.toggle_pin_post_author(p_post_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_me uuid := (SELECT id FROM users WHERE auth_id = auth.uid());
  v_author uuid := (SELECT user_id FROM posts WHERE id = p_post_id);
BEGIN
  IF v_me IS NULL OR v_author IS NULL OR v_author = v_me THEN
    RAISE EXCEPTION 'invalid pin target';
  END IF;

  IF EXISTS (SELECT 1 FROM pinned_people WHERE user_id = v_me AND pinned_user_id = v_author) THEN
    PERFORM public.unpin_person(v_author);
    RETURN false;
  END IF;

  PERFORM public.pin_person(v_author);
  RETURN true;
END;
$$;
