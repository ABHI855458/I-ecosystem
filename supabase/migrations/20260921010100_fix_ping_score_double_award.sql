-- send_ping did its own `ping_score = ping_score + 25` directly, AND the
-- same INSERT INTO pings it performs fires the award_ping_sent_score
-- trigger, which does the identical `ping_score = ping_score + 25` again —
-- same double-award shape as the streak bug fixed in
-- 20260921000100_red_streak_anon_only.sql, caught while verifying that
-- fix. Measured live before this migration: one real send_ping call moved
-- a real user's ping_score by +50, while score_events (the audit log)
-- correctly recorded only one 'ping_sent' row at +25 — the log was right,
-- the balance was double it.
--
-- total_score (COALESCE(glow_score,0) + COALESCE(ping_score,0), generated)
-- is THE single score this app shows everywhere — Ping page, Anon page,
-- profile, leaderboard (see feed_service.dart's own "ONE combined score"
-- comment) — so this bug was inflating the actual number every user sees
-- by +25 per ping sent, not some internal-only field.
--
-- Same fix shape as the streak cleanup: remove the redundant direct
-- increment, leave the trigger (award_ping_sent_score) as the single
-- source of truth. Deliberately NOT a backfill/correction of existing
-- inflated balances — same historical-data-untouched principle as the
-- streak fix; whether to correct already-awarded points is a separate,
-- product-level decision (see this migration's own verification query for
-- exactly which users and by how much, run at apply time).
CREATE OR REPLACE FUNCTION public.send_ping(p_receiver_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid;
  v_thread uuid;
  v_label text;
  v_open_until timestamptz;
begin
  v_me := public.current_user_id();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if p_receiver_id = v_me then raise exception 'Cannot ping yourself.'; end if;

  if public.is_blocked_user(auth.uid(), p_receiver_id) then
    raise exception 'Cannot ping this user.';
  end if;

  select max(expires_at) into v_open_until
    from public.pings
   where sender_id = v_me
     and receiver_id = p_receiver_id
     and status = 'pending'
     and expires_at > now();

  if v_open_until is not null then
    raise exception 'PING_ALREADY_OPEN:%',
      to_char(v_open_until at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  end if;

  if p_anonymous then
    v_label := public.gen_handle();
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours, photo_url)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  returning id into v_thread;

  -- award_ping_sent_score (trigger on this insert) is now the ONLY source
  -- of the +25 ping_score award — no direct update here anymore.
  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours, p_photo_url);

  return v_thread;
end;
$function$;
