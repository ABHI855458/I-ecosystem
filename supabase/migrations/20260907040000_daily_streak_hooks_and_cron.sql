-- ---------------------------------------------------------------------------
-- Feed the daily streak from the two actions that count, and schedule decay.
-- ---------------------------------------------------------------------------

-- An anon post bumps the streak. Folded into the existing +25 award so the
-- two can't disagree about what counted.
create or replace function public.award_anon_post_score()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.users set glow_score = glow_score + 25 where id = new.user_id;
  perform public.bump_daily_streak(new.user_id);
  return new;
end;
$$;

-- A ping sent bumps it too — "anon post OR ping" is the rule.
create or replace function public.send_ping(
  p_receiver_id uuid,
  p_prompt text,
  p_anonymous boolean default false,
  p_window_hours integer default 5
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me uuid;
  v_thread uuid;
  v_label text;
begin
  v_me := public.current_user_id();
  if v_me is null then raise exception 'Not signed in.'; end if;
  if p_receiver_id = v_me then raise exception 'Cannot ping yourself.'; end if;

  if p_anonymous then
    v_label := public.gen_handle();
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours)
  returning id into v_thread;

  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours);

  update public.users set ping_score = ping_score + 25 where id = v_me;
  perform public.bump_daily_streak(v_me);

  return v_thread;
end;
$$;

-- ── Schedule ───────────────────────────────────────────────────────────────
-- ONE global nightly job, per-user cycles driven by each row's own
-- last_decay_at (apply_score_decay only touches rows >20 days overdue).
-- Per-user cron entries would need this same nightly scan anyway, and would
-- add a schedule row per signup.
create extension if not exists pg_cron;

select cron.unschedule('score-decay-nightly')
 where exists (select 1 from cron.job where jobname = 'score-decay-nightly');

select cron.schedule(
  'score-decay-nightly',
  '17 3 * * *',                       -- 03:17 UTC daily, off the hour
  $$ select public.apply_score_decay(); $$
);
