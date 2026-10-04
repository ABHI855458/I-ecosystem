-- ============================================================================
-- Two scoring bugs, both found by asking the database what an action actually
-- earned (my_score_gain_since, 20260907200000):
--
-- 1. SENDING A PING AWARDED NOTHING. The rules say +25 for a ping sent, but
--    `pings` had no award trigger at all — only `ping_replies` did. Verified
--    live: send_ping() credited 0.
--
-- 2. FOUR AWARD PATHS NEVER WROTE THE LEDGER. award_anon_post_score,
--    award_anon_engagement_score, award_ping_reply_score and
--    award_community_reaction_xp updated users.glow_score/ping_score directly
--    and skipped log_score_event, so score_events held only 'daily_open' and
--    'reaction_given'. That makes the ledger useless as an audit trail AND
--    means any "what did I just earn" read (the reward popup) sees zero for
--    most of what a person actually does.
--
-- log_score_event already swallows its own failures by design (the audit
-- trail must never cost someone their points), so adding these calls cannot
-- break the awards they sit next to.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

-- ── 1. Ping sent: +25 ───────────────────────────────────────────────────────
-- On the SENDER. Group pings fan out to one `pings` row per member, so this
-- is scoped to person pings (group_id IS NULL) — otherwise pinging a group of
-- twelve would pay 300.

CREATE OR REPLACE FUNCTION public.award_ping_sent_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.group_id is not null then
    return new;
  end if;
  update public.users set ping_score = ping_score + 25 where id = new.sender_id;
  perform public.log_score_event(new.sender_id, 'ping_sent', 25);
  perform public.bump_daily_streak(new.sender_id);
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_award_ping_sent ON public.pings;
CREATE TRIGGER trg_award_ping_sent
  AFTER INSERT ON public.pings
  FOR EACH ROW EXECUTE FUNCTION public.award_ping_sent_score();

-- ── 2. Ledger writes on the four paths that skipped it ──────────────────────

CREATE OR REPLACE FUNCTION public.award_ping_reply_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.users set ping_score = ping_score + 20 where id = new.replier_id;
  perform public.log_score_event(new.replier_id, 'ping_reply', 20);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.award_anon_post_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.users set glow_score = glow_score + 25 where id = new.user_id;
  perform public.log_score_event(new.user_id, 'anon_post', 25);
  perform public.bump_daily_streak(new.user_id);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.award_anon_engagement_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_owner uuid;
  v_vis text;
begin
  if new.post_id is null then
    return new;
  end if;

  select user_id, visibility into v_owner, v_vis from public.posts where id = new.post_id;

  if v_owner is null or v_vis is distinct from 'anonymous' or v_owner = new.user_id then
    return new;
  end if;

  update public.users set glow_score = glow_score + 5 where id = v_owner;
  perform public.log_score_event(v_owner, 'engagement_received', 5);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.award_community_reaction_xp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  p RECORD;
  wk DATE := current_week_start();
BEGIN
  SELECT user_id, community_id INTO p
    FROM posts
   WHERE id = new.post_id AND visibility = 'anonymous' AND community_id IS NOT NULL;

  IF p.user_id IS NULL OR p.user_id = new.user_id THEN
    RETURN new;
  END IF;

  INSERT INTO community_streaks (community_id, user_id, xp, week_xp, week_start_on, updated_at)
  VALUES (p.community_id, p.user_id, 2, 2, wk, now())
  ON CONFLICT (community_id, user_id) DO UPDATE SET
    xp      = community_streaks.xp + 2,
    week_xp = CASE WHEN community_streaks.week_start_on = wk
                   THEN community_streaks.week_xp + 2 ELSE 2 END,
    week_start_on = wk,
    updated_at    = now();

  PERFORM public.log_score_event(p.user_id, 'community_xp', 2);
  RETURN new;
END $function$;
