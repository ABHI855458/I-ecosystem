-- Fixes notify_activation_drip(), which FAILS ON EVERY RUN that reaches
-- stage 3. Found in cron.job_run_details, not by reading code.
--
-- The `activation-drip` job (*/30) shows 7 failures against 9 successes,
-- every failure identical:
--
--   ERROR:  malformed array literal: "circle"
--   DETAIL: Array value must start with "{" or dimension information.
--   CONTEXT: PL/pgSQL function notify_activation_drip(...) line 60
--
-- Cause: `v_missing := v_missing || 'circle'` where v_missing is text[].
-- `||` is overloaded for BOTH (anyarray, anyarray) and (anyarray,
-- anyelement); an UNTYPED literal resolves to the array form first, so
-- Postgres tries to parse the string 'circle' as an array literal and
-- throws. All three lines (group/album/circle) carry the same defect --
-- whichever one executes first is the one that errors, which is why the
-- message names 'circle' for a user who already has a group and an album.
--
-- Why it looked partly healthy: every earlier stage CONTINUEs out of the
-- loop, so a run only fails once some user actually reaches stage 3 while
-- missing an artifact. The "9 succeeded" runs are simply runs where nobody
-- got that far. In practice the group/album/circle activation nudge has
-- NEVER been delivered, and each failure aborts the whole loop, so users
-- queued behind the failing one get no nudge either.
--
-- Fix: array_append(), unambiguous by signature. Everything else below is
-- reproduced VERBATIM from the live pg_get_functiondef output so this is a
-- faithful CREATE OR REPLACE, not a partial rewrite.

CREATE OR REPLACE FUNCTION public.notify_activation_drip(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_win   text := public.notification_window(p_at);
  v_dips  int;
  r record; st record; v_missing text[]; v_pick text; v_title text; v_age int;
  n int := 0;
BEGIN
  SELECT count(*)::int INTO v_dips FROM public.posts p
   WHERE p.visibility='anonymous' AND p.deleted_at IS NULL
     AND ((p.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date = v_today;

  PERFORM set_config('app.notif_trusted', 'on', true);

  FOR r IN
    SELECT u.id, u.created_at,
           EXTRACT(EPOCH FROM (p_at - (u.created_at AT TIME ZONE 'UTC')))/3600.0 AS hours_old
      FROM public.users u
     WHERE u.deleted_at IS NULL AND u.auth_id IS NOT NULL
  LOOP
    SELECT * INTO st FROM public.activation_state(r.id);
    CONTINUE WHEN st.complete;          -- §6.5: stops entirely. Graduated.

    -- Stage 1 — welcome, first hour.
    IF r.hours_old <= 1 THEN
      INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
      VALUES (r.id, 'activation_nudge', 'standard',
              'Drop your first Dip — takes 10 seconds.',
              jsonb_build_object('screen','composer','feed_scope','anon'),
              'activation_nudge:' || r.id::text || ':install')
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
      n := n + 1;
      CONTINUE;
    END IF;

    -- Stage 2 — +3h, only if they still have not dipped.
    IF r.hours_old >= 3
       AND NOT EXISTS (SELECT 1 FROM public.posts p
                        WHERE p.user_id = r.id AND p.visibility='anonymous'
                          AND p.deleted_at IS NULL) THEN
      INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
      VALUES (r.id, 'activation_nudge', 'standard',
              CASE WHEN v_dips > 0
                   THEN 'Still haven''t dipped? ' || v_dips || ' people already have today.'
                   ELSE 'Still haven''t dipped? Be the first today.' END,
              jsonb_build_object('screen','composer','feed_scope','anon'),
              'activation_nudge:' || r.id::text || ':plus3h')
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
      n := n + 1;
      CONTINUE;
    END IF;

    -- Stage 3 — daily rotating nudge, evening or last call only, once a day.
    CONTINUE WHEN v_win NOT IN ('evening','last_call');
    CONTINUE WHEN r.hours_old < 3;

    v_missing := ARRAY[]::text[];
    -- THE FIX (see header): array_append, not `|| 'literal'`.
    IF NOT st.has_group  THEN v_missing := array_append(v_missing, 'group');  END IF;
    IF NOT st.has_album  THEN v_missing := array_append(v_missing, 'album');  END IF;
    IF NOT st.has_circle THEN v_missing := array_append(v_missing, 'circle'); END IF;
    CONTINUE WHEN cardinality(v_missing) = 0;

    v_age  := GREATEST(0, (v_today - (r.created_at AT TIME ZONE 'UTC')::date));
    v_pick := v_missing[(v_age % cardinality(v_missing)) + 1];

    v_title := CASE v_pick
      WHEN 'group'  THEN 'You haven''t joined or made a group yet — that''s where your people actually are.'
      WHEN 'album'  THEN 'Got someone you''re close with? Start a Us album — it''s just the two of you.'
      ELSE               'Make a Circle — pick exactly who sees your next post.'
    END;

    INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
    VALUES (r.id, 'activation_nudge', 'standard', v_title,
            jsonb_build_object('screen',
              CASE v_pick WHEN 'group' THEN 'groups'
                          WHEN 'album' THEN 'profile'
                          ELSE 'circles' END),
            'activation_nudge:' || r.id::text || ':' || v_today::text)
    ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    n := n + 1;
  END LOOP;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
