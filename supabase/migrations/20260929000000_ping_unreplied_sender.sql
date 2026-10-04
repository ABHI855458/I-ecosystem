-- ============================================================================
-- Tell the SENDER when a 1:1 ping closes unreplied (explicit request):
--   seen_at IS NULL      -> "<name> didn't open your ping"
--   seen_at IS NOT NULL  -> "<name> saw your ping but didn't reply"
-- New type 'ping_unreplied'. Runs inside the existing 15-minute
-- notify-unanswered-pings cron; the recipient-side reminders are unchanged.
-- The type list is rebuilt from the LIVE constraint at authoring time.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'reaction',
  'ping',
  'branch_view',
  'us_album_mutual',
  'report_resolved',
  'report_filed',
  'announcement',
  'ping_answered',
  'us_album_invite',
  'comment',
  'moment_contribution',
  'group_added',
  'group_invite',
  'group_post',
  'group_dip',
  'community_post',
  'friend_post',
  'streak_risk_red',
  'streak_risk_blue',
  'streak_milestone_blue',
  'group_streak_ping',
  'group_streak_risk',
  'group_streak_broken',
  'level_up',
  'level_progress',
  'leaderboard_movement',
  'ping_unanswered',
  'group_ping_waiting',
  'group_ping_replied',
  'pinned_post_view',
  'pinned_group_post_view',
  'moment_new_post',
  'moment_reply_nudge',
  'pinned_profile_view',
  'rank_overtaken',
  'rank_regained',
  'streak_rank_overtaken',
  'start_streak_nudge',
  'streak_standing',
  'window_prompt',
  'break_live_count',
  'midday_report',
  'day_digest',
  'lifecycle_cooling',
  'lifecycle_lapsed',
  'lifecycle_dormant',
  'activation_nudge',
  'graduation',
  'ping_reply_liked',
  'us_album_accepted',
  'group_profile_view',
  'us_album_ended',
  'daily_drop',
  'weekly_recap',
  'ping_unreplied'
]::text[]));

CREATE OR REPLACE FUNCTION public.notify_unanswered_pings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int;
BEGIN
  PERFORM set_config('app.notif_trusted', 'on', true);

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'ping_unanswered', NULL, 'major',
         CASE
           WHEN st.stage = 1 AND nm.name IS NOT NULL
             THEN nm.name || ' is waiting for your reply 🥺'
           WHEN st.stage = 1
             THEN 'Someone''s been waiting 3 hours for you 🥺'
           WHEN nm.name IS NOT NULL
             THEN 'Still no reply? ' || nm.name || ' keeps checking 👀'
           ELSE 'They''re still waiting… 8 hours now 😶'
         END,
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id),
         'ping_unanswered:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '8 hours')) AS st(stage, after)
    LEFT JOIN LATERAL (
      SELECT COALESCE(NULLIF(btrim(u.name), ''), u.anon_name) AS name
        FROM public.users u
       WHERE u.id = p.sender_id AND p.anonymous IS NOT TRUE
    ) nm ON true
   WHERE p.group_id IS NULL
     AND p.receiver_id IS NOT NULL
     AND p.receiver_id <> p.sender_id
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.receiver_id, 'group_ping_waiting', NULL, 'major',
         CASE
           WHEN st.stage = 1 AND tc.replied > 0 AND tc.total - tc.replied = 1
             THEN 'Everyone in ' || COALESCE(g.name,'your group') || ' answered… except you 🥺'
           WHEN st.stage = 1 AND tc.replied > 0
             THEN tc.replied || '/' || tc.total || ' answered in '
                  || COALESCE(g.name,'your group') || ' — tu kab? 👀'
           WHEN st.stage = 1
             THEN COALESCE(g.name,'Your group') || ' is waiting for you 🫣'
           ELSE 'Still waiting on you in ' || COALESCE(g.name,'your group')
                || ' 👀 don''t leave them hanging'
         END,
         p.prompt,
         jsonb_build_object('screen','group','group_id', p.group_id, 'thread_id', p.thread_id),
         'group_ping_waiting:' || p.id::text || ':s' || st.stage
    FROM public.pings p
    JOIN public.groups g ON g.id = p.group_id
    CROSS JOIN LATERAL (VALUES (1, INTERVAL '3 hours'), (2, INTERVAL '5 hours')) AS st(stage, after)
    CROSS JOIN LATERAL (
      SELECT count(*)::int AS total,
             count(*) FILTER (WHERE t.replied_at IS NOT NULL)::int AS replied
        FROM public.pings t
       WHERE t.thread_id = p.thread_id AND t.receiver_id IS NOT NULL
    ) tc
   WHERE p.group_id IS NOT NULL
     AND p.thread_id IS NOT NULL
     AND p.receiver_id IS NOT NULL
     AND p.replied_at IS NULL
     AND p.expires_at > now()
     AND now() >= (p.created_at AT TIME ZONE 'UTC') + st.after
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  -- The SENDER hears about a 1:1 ping that closed without a reply
  -- (explicit request): never opened vs opened-but-no-reply. Once per ping,
  -- only for windows that closed in the last hour so old pings never
  -- resurface.
  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  SELECT p.sender_id, 'ping_unreplied', p.receiver_id, 'standard',
         CASE WHEN p.seen_at IS NULL
              THEN COALESCE(rn.name, 'They') || ' didn''t open your ping'
              ELSE COALESCE(rn.name, 'They') || ' saw your ping but didn''t reply'
         END,
         p.prompt,
         jsonb_build_object('screen','ping','ping_id', p.id,
                            'opened', p.seen_at IS NOT NULL),
         'ping_unreplied:' || p.id::text
    FROM public.pings p
    LEFT JOIN LATERAL (
      SELECT COALESCE(NULLIF(btrim(u.name), ''), u.username) AS name
        FROM public.users u WHERE u.id = p.receiver_id
    ) rn ON true
   WHERE p.group_id IS NULL
     AND p.receiver_id IS NOT NULL
     AND p.receiver_id <> p.sender_id
     AND p.replied_at IS NULL
     AND p.expires_at <= now()
     AND p.expires_at > now() - interval '1 hour'
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS m = ROW_COUNT; n := n + m;

  PERFORM set_config('app.notif_trusted', 'off', true);
  RETURN n;
END;
$function$;

COMMIT;
