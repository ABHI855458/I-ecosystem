-- PHASE 4b/4c/4d/4e.
--
-- 4b  unanswered 1:1 ping         T+3h, T+8h
-- 4c  group ping non-repliers     T+3h, T+5h, addressed individually
-- 4d  start-a-streak nudge        batched + staggered
-- 4e  streak community standing   once/day
--
-- New types for 4d/4e.
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'reaction','ping','friend_request','friend_accepted','branch_view',
    'us_album_mutual','report_resolved','report_filed','announcement',
    'ping_answered','us_album_invite','comment','moment_contribution',
    'group_added','group_post','group_dip','community_post','friend_post',
    'streak_risk_red','streak_risk_blue','streak_milestone_blue',
    'group_streak_ping','group_streak_risk','group_streak_broken',
    'level_up','level_progress','leaderboard_movement','ping_unanswered',
    'group_ping_waiting','group_ping_replied','pinned_post_view',
    'moment_new_post','moment_reply_nudge','pinned_profile_view',
    'rank_overtaken','rank_regained','streak_rank_overtaken',
    'start_streak_nudge','streak_standing'                        -- Phase 4
  ])
);

-- =================== 4b + 4c: ping reminders =========================
-- Replaces notify_unanswered_pings, which sent ONE reminder per ping and,
-- for groups, broadcast it to EVERY member of the thread — repliers
-- included. Someone who had already answered was told "2 people still
-- haven't replied", which is not actionable by them and reads as nagging
-- for something they already did.
--
-- Now:
--   1:1    two stages at T+3h and T+8h from the ping's creation.
--   group  two stages at T+3h and T+5h, sent ONLY to members who have not
--          replied, addressed to them ("you"), never a broadcast count.
--
-- T is created_at in both cases. The old 1:1 rule (seen_at + 3h, else
-- created_at + 12h) is deliberately replaced by the spec's flat T+3h/T+8h:
-- it is simpler to reason about, and it no longer lets a ping the receiver
-- never opened sit silent for half a day.
--
-- Self-cancelling on the same principle as 4a: a replied ping stops
-- matching, so its later stage never sends.
CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  -- ---- 4b: 1:1, stages at +3h and +8h ----
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         CASE WHEN st.stage = 1
              THEN 'Someone is still waiting on you 👀'
              ELSE 'Still unanswered — they pinged you 8 hours ago 👀' END,
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '8 hours')) AS st(stage, after)
   WHERE p.group_id IS NULL
     AND p.receiver_id IS NOT NULL
     AND p.receiver_id <> p.sender_id
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- ---- 4c: group, stages at +3h and +5h, non-repliers only ----
  -- `p` here is the individual member's own ping row inside the thread, so
  -- p.replied_at IS NULL is exactly "this member has not replied". That is
  -- what makes it per-individual instead of a broadcast.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE WHEN st.stage = 1
              THEN COALESCE(g.name,'Your group') || ' is waiting on you 👀'
              ELSE 'Still waiting on you in ' || COALESCE(g.name,'your group') || ' 👀' END,
         p.prompt,
         jsonb_build_object('screen','group','group_id', p.group_id, 'thread_id', p.thread_id),
         'group_ping_waiting:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    JOIN public.groups g ON g.id = p.group_id
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '5 hours')) AS st(stage, after)
   WHERE p.group_id IS NOT NULL
     AND p.thread_id IS NOT NULL
     AND p.receiver_id IS NOT NULL
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ============= 4d: start-a-streak nudge, batched + staggered ==========
-- Zero-streak users only. One per user per day.
--
-- STAGGERING is done by writing push_after, not by sleeping: the dispatcher
-- already selects on `push_after <= now()`, so spreading that column spreads
-- the actual sends with no long-running job and nothing to resume if the
-- worker restarts.
--
--   BATCH SIZE       50 recipients share a send slot
--   STAGGER INTERVAL 3 minutes between consecutive batches
--
-- So recipients 1-50 go at the base time, 51-100 three minutes later, and so
-- on. 50/3min was chosen against the real dispatcher: notify-dispatch pulls
-- `.limit(500)` per sweep and sends sequentially, one FCM call per token, so
-- a slot of 50 is comfortably inside one sweep's budget while keeping any
-- single burst small enough not to look like a spam wave to FCM. At this
-- campus's scale the whole eligible set fits in the first batch or two; the
-- structure matters when it does not.
--
-- Ordering is by user id, not by score or recency — a stable, arbitrary
-- order so nobody is systematically always last.
CREATE OR REPLACE FUNCTION public.notify_start_streak_nudge(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  c_batch   constant int := 50;
  c_stagger constant interval := INTERVAL '3 minutes';
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH eligible AS (
    SELECT u.id,
           (row_number() OVER (ORDER BY u.id) - 1) AS seq
      FROM public.users u
     WHERE u.deleted_at IS NULL
       AND u.auth_id IS NOT NULL
       AND COALESCE(u.daily_streak, 0) = 0
  )
  INSERT INTO public.notifications
    (recipient_id, type, tier, title, data, dedupe_key, push_after)
  SELECT e.id, 'start_streak_nudge', 'minor',
         'Start a 🔴 streak today — one anon post is all it takes',
         jsonb_build_object('screen','composer','feed_scope','anon'),
         'start_streak_nudge:' || e.id::text || ':' || v_today::text,
         -- the stagger
         p_at + ((e.seq / c_batch) * c_stagger)
    FROM eligible e
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

-- ================= 4e: streak community standing =====================
-- Where the user actually stands, once a day, on their BEST community.
--
-- One notification per user, not one per community: a member of six
-- communities would otherwise get six standing notices every evening, which
-- turns a status line into spam. Their strongest position is the one worth
-- telling them about.
--
-- Real rank and real member count, computed at send time from the same
-- ordering community_leaderboard uses, so the numbers match the board they
-- can open. Users with no community, or ranked alone, produce nothing.
CREATE OR REPLACE FUNCTION public.notify_streak_standing(p_at timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_today date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  n int := 0;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  WITH ranked AS (
    SELECT c.id AS community_id, c.name AS cname, u.id AS user_id,
           row_number() OVER (
             PARTITION BY c.id
             ORDER BY public.effective_community_streak(u.daily_streak, u.daily_streak_last) DESC,
                      COALESCE(cs.xp,0) DESC, u.id) AS rnk,
           count(*) OVER (PARTITION BY c.id) AS members
      FROM public.communities c
      JOIN public.community_members cm ON cm.community_id = c.id
      JOIN public.users u ON u.auth_id = cm.user_id
      LEFT JOIN public.community_streaks cs ON cs.community_id = c.id AND cs.user_id = u.id
     WHERE c.deleted_at IS NULL AND u.deleted_at IS NULL
  ),
  best AS (
    SELECT DISTINCT ON (user_id) user_id, community_id, cname, rnk, members
      FROM ranked
     WHERE members > 1          -- "#1 of 1" is not a standing
     ORDER BY user_id, rnk ASC, members DESC
  )
  INSERT INTO public.notifications (recipient_id, type, tier, title, data, dedupe_key)
  SELECT b.user_id, 'streak_standing', 'minor',
         'You''re #' || b.rnk || ' of ' || b.members || ' in ' || b.cname || ' by streak',
         jsonb_build_object('screen','community','community_id', b.community_id),
         'streak_standing:' || b.user_id::text || ':' || v_today::text
    FROM best b
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;
