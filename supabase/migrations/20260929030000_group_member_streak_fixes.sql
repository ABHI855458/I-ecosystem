-- Group ping streaks (the flame on group cards in the Friends feed is each
-- member's OWN reply streak). Rule, by product request: reply to the day's
-- group ping and your streak goes on; don't, and only YOU lose it — nobody
-- else in the group is affected. Three fixes:
--
--   1. Streaks now run over GROUP PING DAYS, not calendar days. A day on
--      which nobody sent a group ping has nothing to reply to, so it no
--      longer breaks anyone (it used to zero every member's flame).
--   2. The flame counts today's reply right away (+1 as soon as you reply),
--      instead of waiting for the midnight resolve.
--   3. One free miss per member per 7 days (streak freeze), same as pair
--      ping streaks.
-- The group-level streak (all members replied) follows rules 1 and 3 too.

alter table public.group_ping_member_streaks
  add column if not exists freeze_used_on date;

-- The group's most recent ping day before p_date (null if none).
create or replace function public.group_prev_ping_day(p_group uuid, p_date date)
returns date
language sql stable security definer
set search_path = public, pg_temp
as $$
  select max(on_date) from public.group_ping_days
   where group_id = p_group and on_date < p_date;
$$;
revoke all on function public.group_prev_ping_day(uuid, date) from public, anon, authenticated;

create or replace function public.resolve_group_ping_day(p_date date)
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  d             record;
  v_prev        date;
  v_replied     uuid[];
  v_all_replied boolean;
  v_freeze      boolean;
  n             int := 0;
begin
  for d in select * from public.group_ping_days
            where on_date = p_date and not resolved loop

    v_prev := public.group_prev_ping_day(d.group_id, p_date);

    select coalesce(array_agg(distinct r.replier_id), '{}')
      into v_replied
      from public.ping_replies r
      join public.pings p on p.id = r.ping_id
     where p.thread_id = d.thread_id;

    select bool_and(m = any(v_replied)) into v_all_replied
      from unnest(d.member_ids) m;
    v_all_replied := coalesce(v_all_replied, false);

    -- ── group-level streak ──
    select not v_all_replied
           and coalesce(gs.current_streak, 0) > 0
           and gs.last_complete_on is not distinct from v_prev
           and (gs.freeze_used_on is null or gs.freeze_used_on <= p_date - 7)
      into v_freeze
      from public.group_ping_streaks gs where gs.group_id = d.group_id;
    v_freeze := coalesce(v_freeze, false);

    insert into public.group_ping_streaks as gs
      (group_id, current_streak, longest_streak, last_complete_on)
    values (d.group_id,
            case when v_all_replied then 1 else 0 end,
            case when v_all_replied then 1 else 0 end,
            case when v_all_replied then p_date end)
    on conflict (group_id) do update set
      current_streak = case
        when v_freeze then gs.current_streak
        when not v_all_replied then 0
        when gs.last_complete_on is not distinct from v_prev then gs.current_streak + 1
        else 1 end,
      longest_streak = greatest(gs.longest_streak, case
        when v_freeze then gs.current_streak
        when not v_all_replied then 0
        when gs.last_complete_on is not distinct from v_prev then gs.current_streak + 1
        else 1 end),
      last_complete_on = case when v_all_replied or v_freeze then p_date
                              else gs.last_complete_on end,
      freeze_used_on = case when v_freeze then p_date else gs.freeze_used_on end,
      updated_at = now();

    -- ── each member's own streak: repliers go on ──
    insert into public.group_ping_member_streaks as ms
      (group_id, user_id, current_streak, longest_streak, last_reply_on)
    select d.group_id, m, 1, 1, p_date
      from unnest(d.member_ids) m
     where m = any(v_replied)
    on conflict (group_id, user_id) do update set
      current_streak = case when ms.last_reply_on is not distinct from v_prev
                            then ms.current_streak + 1 else 1 end,
      longest_streak = greatest(ms.longest_streak,
                        case when ms.last_reply_on is not distinct from v_prev
                             then ms.current_streak + 1 else 1 end),
      last_reply_on = p_date,
      updated_at = now();

    -- ── non-repliers: weekly freeze if available, else only THEY reset ──
    update public.group_ping_member_streaks ms
       set last_reply_on = p_date,          -- bridged, count unchanged
           freeze_used_on = p_date,
           updated_at = now()
     where ms.group_id = d.group_id
       and ms.user_id = any(d.member_ids)
       and not (ms.user_id = any(v_replied))
       and ms.current_streak > 0
       and ms.last_reply_on is not distinct from v_prev
       and (ms.freeze_used_on is null or ms.freeze_used_on <= p_date - 7);

    update public.group_ping_member_streaks
       set current_streak = 0, updated_at = now()
     where group_id = d.group_id
       and user_id = any(d.member_ids)
       and not (user_id = any(v_replied))
       and last_reply_on is distinct from p_date;   -- not just frozen above

    update public.group_ping_days set resolved = true
     where group_id = d.group_id and on_date = p_date;

    n := n + 1;
  end loop;
  return n;
end $$;

-- The flame: each member's live streak — alive if they kept up through the
-- group's last ping day, +1 the moment they reply to today's ping.
create or replace function public.group_ping_member_streak_map(p_group_id uuid)
returns table(user_id uuid, streak integer)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with t as (select (now() at time zone 'Asia/Kolkata')::date as today),
  last_day as (
    select public.group_prev_ping_day(p_group_id, (select today from t)) as d
  ),
  today_row as (
    select gd.thread_id from public.group_ping_days gd
     where gd.group_id = p_group_id and gd.on_date = (select today from t)
  ),
  replied_today as (
    select distinct r.replier_id as uid
      from public.ping_replies r
      join public.pings p on p.id = r.ping_id
     where p.thread_id = (select thread_id from today_row)
  )
  select gm.user_id,
         (case
            when ms.last_reply_on is not null
                 and ((select d from last_day) is null
                      or ms.last_reply_on >= (select d from last_day))
              then coalesce(ms.current_streak, 0)
            else 0 end)
         + case when gm.user_id in (select uid from replied_today)
                     and ms.last_reply_on is distinct from (select today from t)
                then 1   -- a dead streak's base is 0, so replying today shows 1
                else 0 end
    from public.group_members gm
    left join public.group_ping_member_streaks ms
      on ms.group_id = gm.group_id and ms.user_id = gm.user_id
   where gm.group_id = p_group_id
     and public.is_group_member(p_group_id, public.current_user_id());
$function$;

-- Group-level number (Ping page wall badge): same "ping days, not calendar
-- days" freshness.
create or replace function public.group_ping_streak(p_group_id uuid)
returns table(current_streak integer, longest_streak integer, today_replied integer, today_total integer, today_open boolean)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me    uuid := public.current_user_id();
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_last  date;
  v_day   record;
begin
  if v_me is null or not public.is_group_member(p_group_id, v_me) then
    return;
  end if;
  v_last := public.group_prev_ping_day(p_group_id, v_today);

  select * into v_day from public.group_ping_days
   where group_id = p_group_id and on_date = v_today;

  return query
  select
    case
      when gs.last_complete_on is null then 0
      when v_last is null or gs.last_complete_on >= v_last then coalesce(gs.current_streak, 0)
      else 0
    end,
    coalesce(gs.longest_streak, 0),
    case when v_day is null then 0 else (
      select count(distinct r.replier_id)::int
        from public.ping_replies r
        join public.pings p on p.id = r.ping_id
       where p.thread_id = v_day.thread_id
         and r.replier_id = any(v_day.member_ids)
    ) end,
    case when v_day is null then 0 else array_length(v_day.member_ids, 1) end,
    (v_day is not null)
  from (select 1) _
  left join public.group_ping_streaks gs on gs.group_id = p_group_id;
end $function$;
