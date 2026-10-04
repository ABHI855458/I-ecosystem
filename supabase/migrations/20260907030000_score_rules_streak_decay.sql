-- ---------------------------------------------------------------------------
-- The scoring rules that were missing, the server-side daily streak, and the
-- 20-day decay job.
--
-- Which HALF each rule lands in matters, because decay hits them at different
-- rates (anon harder than ping at every level). Convention used here:
--   * anything about anonymous CONTENT or engagement -> glow_score
--   * anything about reaching out / showing up       -> ping_score
-- ---------------------------------------------------------------------------

-- score_events was a dead ledger: 0 rows, and its apply_score trigger wrote to
-- profiles.score — a different legacy table — so it scored nothing and would
-- now double-count against users. Drop the trigger, keep the table as a real
-- append-only audit trail written by the functions below.
drop trigger if exists trg_apply_score on public.score_events;

create or replace function public.log_score_event(
  p_user uuid, p_type text, p_points integer
) returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  insert into public.score_events (user_id, event_type, points)
  values (p_user, p_type, p_points);
$$;

-- ── Daily streak: anon post OR ping sent ───────────────────────────────────
-- One shared helper so both entry points can't drift apart.
create or replace function public.bump_daily_streak(p_user uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_last date;
begin
  select daily_streak_last into v_last from public.users where id = p_user;

  if v_last = current_date then
    return;                                  -- already counted today
  elsif v_last = current_date - 1 then
    update public.users
       set daily_streak = daily_streak + 1,
           daily_streak_last = current_date
     where id = p_user;                      -- consecutive day
  else
    update public.users
       set daily_streak = 1,
           daily_streak_last = current_date
     where id = p_user;                      -- first day, or the run broke
  end if;
end;
$$;

-- ── +3 for a comment GIVEN on someone else's post ──────────────────────────
-- The existing award_anon_engagement_score pays the post's OWNER (+5). This
-- is the other side of that exchange, which nothing scored before.
create or replace function public.award_comment_given_score()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_owner uuid;
begin
  if new.post_id is null then return new; end if;
  select user_id into v_owner from public.posts where id = new.post_id;
  if v_owner is null or v_owner = new.user_id then
    return new;                              -- never score your own post
  end if;
  update public.users set glow_score = glow_score + 3 where id = new.user_id;
  perform public.log_score_event(new.user_id, 'comment_given', 3);
  return new;
end;
$$;

drop trigger if exists trg_award_comment_given on public.comments;
create trigger trg_award_comment_given
  after insert on public.comments
  for each row execute function public.award_comment_given_score();

-- ── +2 for a reaction GIVEN on someone else's post ─────────────────────────
create or replace function public.award_reaction_given_score()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_owner uuid;
begin
  if new.post_id is null then return new; end if;
  select user_id into v_owner from public.posts where id = new.post_id;
  if v_owner is null or v_owner = new.user_id then
    return new;
  end if;
  update public.users set glow_score = glow_score + 2 where id = new.user_id;
  perform public.log_score_event(new.user_id, 'reaction_given', 2);
  return new;
end;
$$;

drop trigger if exists trg_award_reaction_given on public.reactions;
create trigger trg_award_reaction_given
  after insert on public.reactions
  for each row execute function public.award_reaction_given_score();

drop trigger if exists trg_award_realmoji_given on public.post_realmoji_reactions;
create trigger trg_award_realmoji_given
  after insert on public.post_realmoji_reactions
  for each row execute function public.award_reaction_given_score();

-- ── +2 for the first app open of the day ───────────────────────────────────
-- Called by the client on launch; idempotent per day server-side, so a
-- double-call (cold start + resume) can't pay twice.
create or replace function public.record_daily_open()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me uuid;
  v_last date;
begin
  v_me := public.current_user_id();
  if v_me is null then return 0; end if;

  select last_open_at into v_last from public.users where id = v_me;
  if v_last = current_date then
    return 0;                                -- already paid today
  end if;

  update public.users
     set ping_score = ping_score + 2,
         last_open_at = current_date
   where id = v_me;
  perform public.log_score_event(v_me, 'daily_open', 2);
  return 2;
end;
$$;

revoke all on function public.record_daily_open() from public;
grant execute on function public.record_daily_open() to authenticated;

-- ── 20-day decay, tiered by level AT decay time ────────────────────────────
-- Unconditional (applies to everyone), per-user cycle driven by that user's
-- own last_decay_at, run by ONE global nightly job. total_score and level are
-- generated columns, so both re-derive themselves from these two writes —
-- which is what lets a user drop a level here with no second update.
create or replace function public.apply_score_decay()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_count integer;
begin
  with due as (
    select id, level, glow_score, ping_score
      from public.users
     where last_decay_at < now() - interval '20 days'
     for update
  ),
  rates as (
    select
      id,
      glow_score,
      ping_score,
      case when level <= 2 then 0.20 when level <= 5 then 0.40 else 0.50 end as anon_cut,
      case when level <= 2 then 0.15 when level <= 5 then 0.30 else 0.40 end as ping_cut
    from due
  ),
  applied as (
    update public.users u
       set glow_score = greatest(0, floor(r.glow_score * (1 - r.anon_cut))::int),
           ping_score = greatest(0, floor(r.ping_score * (1 - r.ping_cut))::int),
           last_decay_at = now()
      from rates r
     where u.id = r.id
    returning u.id
  )
  select count(*) into v_count from applied;

  return v_count;
end;
$$;
