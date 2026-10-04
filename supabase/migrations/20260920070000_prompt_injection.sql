-- INSTANT PROMPT INJECTION — push a prompt into the live prompt bar
-- mid-window, where it runs alongside the standing rotation and expires
-- with the window.
--
-- ============================ SCHEMA =================================
ALTER TABLE public.daily_prompts
  ADD COLUMN IF NOT EXISTS is_injected boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS injected_at timestamptz;

COMMENT ON COLUMN public.daily_prompts.is_injected IS
  'True for a prompt pushed into ONE live window from the dashboard, as '
  'opposed to a member of the standing rotation pool. Never counted in the '
  'rotation (see pick_window_prompt) — it wins outright while its window is '
  'live and is invisible outside it.';
COMMENT ON COLUMN public.daily_prompts.injected_at IS
  'When the injection happened. This is the expiry mechanism: the prompt is '
  'only visible while this timestamp falls inside the live occurrence of its '
  'own window, so it dies at the window boundary with no cron or cleanup.';

CREATE INDEX IF NOT EXISTS daily_prompts_injected_idx
  ON public.daily_prompts (community_id, injected_at DESC)
  WHERE is_injected;

-- ======================== WINDOW BOUNDARIES ==========================
-- The start/end of ONE occurrence of a window, on a given campus day.
--
-- End is the next window's start by sort_order; the last window of the day
-- (wind_down, 22:30) runs until the first window of the NEXT day (07:30),
-- so it is the one that crosses midnight and needs the +1 day.
--
-- Everything is computed in Asia/Kolkata and returned as timestamptz, so a
-- caller comparing injected_at against these is comparing absolute instants
-- and the server's own timezone never enters into it.
CREATE OR REPLACE FUNCTION public.window_bounds(p_window text, p_day date)
RETURNS TABLE(starts timestamptz, ends timestamptz)
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH w AS (
    SELECT pw.starts_at, pw.sort_order
      FROM public.prompt_windows pw WHERE pw.key = p_window
  ),
  nxt AS (
    SELECT pw.starts_at
      FROM public.prompt_windows pw, w
     WHERE pw.sort_order = w.sort_order + 1
  )
  SELECT
    ((p_day + (SELECT starts_at FROM w)) AT TIME ZONE 'Asia/Kolkata'),
    CASE
      WHEN EXISTS (SELECT 1 FROM nxt)
        THEN ((p_day + (SELECT starts_at FROM nxt)) AT TIME ZONE 'Asia/Kolkata')
      -- Last window of the day: runs to the first window of the next.
      ELSE (((p_day + 1) + (SELECT min(starts_at) FROM public.prompt_windows))
              AT TIME ZONE 'Asia/Kolkata')
    END
  FROM w;
$function$;

-- ========================= THE PICKER ================================
-- Same day-index rotation as before (20260920000000), with exactly two
-- additions:
--
--   1. FRONT-CHECK. An injected prompt for this community+window whose
--      injected_at falls inside THIS occurrence of the window wins
--      outright, before the rotation is consulted at all.
--
--      Ties: most recent injected_at wins — ORDER BY injected_at DESC.
--      Explicit, because "admin injects, changes their mind, injects
--      again" is a real sequence and leaving it to whichever row sorted
--      first would make it unpredictable.
--
--      Expiry falls out of the boundary comparison: once the window rolls,
--      injected_at is no longer inside the live occurrence, and tomorrow's
--      occurrence of the same window has boundaries a day later that a
--      yesterday timestamp can never satisfy. No cron, no cleanup, no
--      expires_at to forget to set.
--
--   2. The rotation pool now excludes is_injected rows. Without this an
--      injection would be counted into pool_size and shift
--      (day_index MOD pool_size) for every other prompt — one injection
--      would silently re-order the whole 14-day cycle.
CREATE OR REPLACE FUNCTION public.pick_window_prompt(p_community_id uuid, p_window text, p_day date, p_feed_scope text DEFAULT 'everyone'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_use_specific boolean;
  v_scope        text;
  v_salt         text;
  v_day_index    bigint;
  v_id           uuid;
  v_starts       timestamptz;
  v_ends         timestamptz;
BEGIN
  -- ---- 1. Injected prompt takes the window, if one is live -----------
  SELECT b.starts, b.ends INTO v_starts, v_ends
    FROM public.window_bounds(p_window, p_day) b;

  SELECT dp.id INTO v_id
    FROM public.daily_prompts dp
   WHERE dp.is_injected
     AND dp.active
     AND dp.community_id = p_community_id
     AND p_window = ANY(dp.time_windows)
     AND dp.injected_at >= v_starts
     AND dp.injected_at <  v_ends
   ORDER BY dp.injected_at DESC
   LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  -- ---- 2. Otherwise the standing rotation, untouched -----------------
  v_salt := p_community_id::text || p_window;
  v_day_index := (p_day - DATE '2026-01-01');

  FOREACH v_scope IN ARRAY ARRAY[
    p_feed_scope,
    CASE WHEN p_feed_scope = 'anon' THEN 'everyone' ELSE 'anon' END
  ] LOOP
    v_use_specific := TRUE;

    FOR i IN 1..2 LOOP
      SELECT x.id INTO v_id
      FROM (
        SELECT dp.id,
               row_number() OVER (
                 ORDER BY
                   (abs(hashtext(dp.id::text || v_salt)) % 10000)::numeric
                     / GREATEST(dp.weight, 1),
                   dp.id
               ) - 1 AS rn,
               count(*) OVER () AS pool
          FROM public.daily_prompts dp
         WHERE dp.active
           -- Injections are never part of the cycle; see note 2 above.
           AND NOT dp.is_injected
           AND dp.feed_scope = v_scope
           AND (dp.expires_at IS NULL OR dp.expires_at > now())
           AND (dp.time_windows IS NULL
                OR cardinality(dp.time_windows) = 0
                OR p_window = ANY(dp.time_windows))
           AND (CASE WHEN v_use_specific
                     THEN dp.community_id = p_community_id
                     ELSE dp.community_id IS NULL END)
      ) x
      WHERE x.rn = ((v_day_index % x.pool) + x.pool) % x.pool;

      EXIT WHEN v_id IS NOT NULL;
      v_use_specific := NOT v_use_specific;
    END LOOP;

    EXIT WHEN v_id IS NOT NULL;
  END LOOP;

  RETURN v_id;
END;
$function$;

-- ========================== THE WRITE PATH ===========================
-- The dashboard's "Add to current rotation" action.
--
-- The window is resolved SERVER-SIDE, here, at insert time — not chosen in
-- the UI and not detected when the page loaded. That is deliberate: if the
-- dashboard detected "lunch" at page load and the admin submitted 40
-- minutes later, the row would be stamped for a window that had already
-- closed and would silently never appear. Resolving it at the same instant
-- injected_at is stamped makes the two agree by construction, so the
-- boundary race cannot happen.
--
-- Late injection is therefore unreachable through this path. If a row is
-- ever crafted by hand with an injected_at outside its window's occurrence,
-- it simply never surfaces — wasted rather than queued, which is the
-- intended product behaviour: a prompt written for a moment that has passed
-- showing up ~20 hours later, out of context, in a backlog the admin can
-- neither see nor cancel, is worse than it not showing at all.
--
-- Ping prompts: an admin injecting mid-day has no time to write ten, so the
-- generic per-scope fallback set is copied onto the new prompt as linked
-- rows. Never zero — ping_prompts_for_post's own fallback would cover it,
-- but copying makes what the prompt will actually offer visible and
-- editable in the dashboard right after insert.
CREATE OR REPLACE FUNCTION public.inject_prompt(
  p_community_id uuid,
  p_prompt_text  text,
  p_feed_scope   text DEFAULT 'anon',
  p_prompt_kind  text DEFAULT 'photo'
)
RETURNS TABLE(prompt_id uuid, window_key text, ping_prompts_attached integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_window text;
  v_day    date;
  v_id     uuid;
  v_pings  int := 0;
BEGIN
  IF btrim(coalesce(p_prompt_text, '')) = '' THEN
    RAISE EXCEPTION 'Prompt text is required.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.communities
                  WHERE id = p_community_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Unknown or inactive community.';
  END IF;

  SELECT w.window_key, w.for_day INTO v_window, v_day
    FROM public.current_prompt_window() w;

  INSERT INTO public.daily_prompts
    (prompt_text, community_id, prompt_kind, feed_scope, time_windows,
     weight, active, category, is_injected, injected_at)
  VALUES
    (btrim(p_prompt_text), p_community_id, p_prompt_kind, p_feed_scope,
     ARRAY[v_window]::text[], 5, true, 'injected', true, now())
  RETURNING id INTO v_id;

  -- Copy the generic fallback set for this feed scope onto the new prompt.
  INSERT INTO public.ping_prompts
    (prompt_text, daily_prompt_id, pool, prompt_kind, weight, active)
  SELECT pp.prompt_text, v_id, 'linked', pp.prompt_kind, pp.weight, true
    FROM public.ping_prompts pp
   WHERE pp.pool = 'fallback'
     AND pp.active
   ORDER BY pp.created_at
   LIMIT 10;
  GET DIAGNOSTICS v_pings = ROW_COUNT;

  RETURN QUERY SELECT v_id, v_window, v_pings;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.inject_prompt(uuid, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.inject_prompt(uuid, text, text, text) TO authenticated;
