-- Freshness recovers with time, not just a permanent count-based floor.
--
-- OLD (verified against real data before this change — see the report):
--   seen_count <= 0 -> 1.0
--   seen_count = 1  -> 0.7
--   seen_count >= 2 -> 0.4, forever
-- `last_seen_at` was stored but never read by the scoring formula. Two
-- real prompt_impressions rows for the same user, same community
-- (abisheksdpatel / RVCE): "The spot on campus you'd defend..." seen 7x,
-- last seen 2026-09-14, and "Show what the parking looks like..." seen 6x,
-- last seen 2026-09-19 (today) — both scored freshness 0.4, identically,
-- despite a 5-day gap in recency. Once a prompt crosses 2 views it can
-- never look fresher again, no matter how long it's been.
--
-- NEW: same count-based floor as the "just seen" state (unchanged
-- thresholds — 0.7 once, 0.4 for 2+), then linearly recovered toward 1.0
-- over the 14 days since last_seen_at. 14, not some other window, because
-- it matches this project's own content cadence (the Wake pilot's 14-slot
-- sets) — a prompt goes a full round-trip of a community's pool in that
-- time. At 0 days since last seen: identical to the old floor. At 14+
-- days: fully recovered to 1.0, same as never seen. Every affinity/drift/
-- social_proof/novelty term is untouched — this is the only weight that
-- changes, per instruction.
CREATE OR REPLACE FUNCTION public.prompt_bar_for_user(p_feed_scope text DEFAULT 'everyone'::text, p_at timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(community_id uuid, community_name text, prompt_id uuid, prompt_text text, prompt_kind text, window_key text, response_count integer, score numeric, affinity numeric, drift numeric, freshness numeric, social_proof numeric, novelty numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me       uuid;
  v_auth     uuid;
  v_window   text;
  v_day      date;
  v_prev_win text;
  v_prev_com uuid;
  v_joined   timestamptz;
  v_n_comms  int;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RETURN; END IF;
  SELECT u.auth_id INTO v_auth FROM public.users u WHERE u.id = v_me;

  SELECT w.window_key, w.for_day INTO v_window, v_day
    FROM public.current_prompt_window(p_at) w;

  SELECT w.key INTO v_prev_win
    FROM public.prompt_windows w
   WHERE w.sort_order = (SELECT sort_order - 1 FROM public.prompt_windows WHERE key = v_window);
  SELECT h.community_id INTO v_prev_com
    FROM public.prompt_bar_history h
   WHERE h.user_id = v_me AND h.for_day = v_day AND h.window_key = v_prev_win;

  SELECT count(*) INTO v_n_comms
    FROM public.community_members cm WHERE cm.user_id = v_auth;

  SELECT min(cm.joined_at) INTO v_joined
    FROM public.community_members cm WHERE cm.user_id = v_auth;

  RETURN QUERY
  WITH mine AS (
    SELECT c.id, c.name
      FROM public.community_members cm
      JOIN public.communities c ON c.id = cm.community_id
     WHERE cm.user_id = v_auth
       AND c.deleted_at IS NULL
       -- Rule 4: first 48h, structural (auto-joined) communities only.
       AND (
         v_joined IS NULL
         OR public.campus_now() > (v_joined + interval '48 hours')
         OR cm.joined_at <= v_joined + interval '1 minute'
       )
  ),
  picked AS (
    SELECT m.id, m.name,
           public.pick_window_prompt(m.id, v_window, v_day, p_feed_scope) AS pid,
           public.window_affinity_for(m.id, v_window) AS aff
      FROM mine m
  ),
  eligible AS (
    SELECT * FROM picked WHERE pid IS NOT NULL
  ),
  -- Rule 3: drop affinity 0, but never return nothing. If every community
  -- is 0 in this window, keep the best of them.
  kept AS (
    SELECT * FROM eligible WHERE aff > 0
    UNION ALL
    SELECT * FROM eligible
     WHERE NOT EXISTS (SELECT 1 FROM eligible WHERE aff > 0)
       AND aff = (SELECT max(aff) FROM eligible)
  ),
  scored AS (
    SELECT
      p.id, p.name, p.pid, p.aff,
      (WITH last_post AS (
         SELECT max(po.created_at) AS at
           FROM public.posts po
          WHERE po.user_id = v_me AND po.community_id = p.id
            AND po.deleted_at IS NULL
       )
       SELECT CASE
         WHEN at IS NULL THEN 1.8
         WHEN at::date = public.campus_now()::date THEN 1.0
         WHEN at > public.campus_now() - interval '3 days'  THEN 1.3
         WHEN at > public.campus_now() - interval '6 days'  THEN 1.8
         WHEN at > public.campus_now() - interval '11 days' THEN 2.5
         ELSE 1.2
       END FROM last_post) AS drift,
      COALESCE((
        SELECT CASE
          WHEN pi.seen_count <= 0 THEN 1.0
          ELSE LEAST(1.0,
            (CASE WHEN pi.seen_count = 1 THEN 0.7 ELSE 0.4 END)
            + (1.0 - (CASE WHEN pi.seen_count = 1 THEN 0.7 ELSE 0.4 END))
              * LEAST(1.0,
                  GREATEST(0.0,
                    EXTRACT(EPOCH FROM (public.campus_now() - pi.last_seen_at))
                  ) / (14 * 86400.0)
                )
          )
        END
          FROM public.prompt_impressions pi
         WHERE pi.user_id = v_me AND pi.prompt_id = p.pid), 1.0) AS fresh,
      (WITH r AS (
         SELECT count(*) AS n FROM public.posts po
          WHERE po.prompt_id = p.pid AND po.deleted_at IS NULL
            AND po.created_at > (public.campus_now() - interval '1 hour')
       )
       SELECT CASE WHEN n = 0 THEN 0.8
                   WHEN n < 5 THEN 1.0
                   WHEN n < 16 THEN 1.2
                   ELSE 1.4 END FROM r) AS proof,
      CASE WHEN v_n_comms < 3 THEN 1.0
           WHEN p.id = v_prev_com THEN 0.3
           ELSE 1.0 END AS nov
    FROM kept p
  )
  SELECT
    s.id, s.name, s.pid, dp.prompt_text, dp.prompt_kind, v_window,
    (SELECT count(*)::int FROM public.posts po
      WHERE po.prompt_id = s.pid AND po.deleted_at IS NULL
        AND po.created_at > (public.campus_now() - interval '6 hours')),
    round(s.aff * s.drift * s.fresh * s.proof * s.nov, 4),
    s.aff, s.drift, s.fresh, s.proof, s.nov
  FROM scored s
  JOIN public.daily_prompts dp ON dp.id = s.pid
  ORDER BY 8 DESC, random();
END;
$function$;
