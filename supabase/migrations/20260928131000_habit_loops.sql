-- Habit loops, by product request:
--   1. ONE daily drop at a random time (11:00–21:00 IST) replaces the eight
--      time-window prompt pushes. Tapping it opens the camera answering the
--      day's prompt (a Dip). The in-app prompt bar still rotates by window.
--   2. Reactions are batched: the first reaction waits 15 min so more fold
--      in, then only milestones (5/10/25/50/100) push again —
--      "🔥 12 reactions on your Dip" instead of a push per reaction.
--   3. A weekly curiosity recap (Sunday 19:00 IST):
--      "👀 4 people from CS viewed your profile this week · 2 of them saw
--      your Dip". Counts and branches only — never who.
--   4. Streak freezes: a streak survives one missed day per week — pair
--      ping streaks (computed on read) and group ping streaks (resolved
--      nightly).

-- ── notification types ────────────────────────────────────────────────────
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type = any (array[
  'reaction','ping','branch_view','us_album_mutual','report_resolved','report_filed',
  'announcement','ping_answered','us_album_invite','comment','moment_contribution',
  'group_added','group_invite','group_post','group_dip','community_post','friend_post',
  'streak_risk_red','streak_risk_blue','streak_milestone_blue','group_streak_ping',
  'group_streak_risk','group_streak_broken','level_up','level_progress',
  'leaderboard_movement','ping_unanswered','group_ping_waiting','group_ping_replied',
  'pinned_post_view','pinned_group_post_view','moment_new_post','moment_reply_nudge',
  'pinned_profile_view','rank_overtaken','rank_regained','streak_rank_overtaken',
  'start_streak_nudge','streak_standing','window_prompt','break_live_count',
  'midday_report','day_digest','lifecycle_cooling','lifecycle_lapsed','lifecycle_dormant',
  'activation_nudge','graduation','ping_reply_liked','us_album_accepted',
  'group_profile_view','us_album_ended',
  'daily_drop','weekly_recap'
]::text[]));

-- ── 1. daily drop ─────────────────────────────────────────────────────────
-- The eight window pushes go; notify_window_change() itself stays (unused).
do $$
declare j text;
begin
  foreach j in array array['window-prompt-wake','window-prompt-preclass','window-prompt-snack',
                           'window-prompt-lunch','window-prompt-dayend','window-prompt-evening',
                           'window-prompt-lastcall','window-prompt-winddown'] loop
    if exists (select 1 from cron.job where jobname = j) then
      perform cron.unschedule(j);
    end if;
  end loop;
end $$;

-- Today's drop moment: 11:00 IST + a salted-hash offset of 0–599 minutes.
-- Salted so nobody can compute tomorrow's time from the date alone.
create or replace function public.daily_drop_at(p_day date)
returns timestamptz
language sql stable security definer
set search_path = public, pg_temp
as $$
  select ((p_day::timestamp + interval '11 hours'
           + make_interval(mins => (('x' || left(md5(
               coalesce((select value from public.private_settings where key = 'viewer_key_salt'), '')
               || ':drop:' || p_day::text), 8))::bit(32)::bigint % 600)::int))
          at time zone 'Asia/Kolkata');
$$;
revoke all on function public.daily_drop_at(date) from public, anon, authenticated;

create or replace function public.notify_daily_drop(p_at timestamptz default now())
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_day    date := (p_at at time zone 'Asia/Kolkata')::date;
  v_window text;
  v_dips   int;
  c_batch  constant int := 50;
  c_stagger constant interval := interval '1 minute';
  n int := 0;
begin
  if p_at < public.daily_drop_at(v_day) then return 0; end if;
  if exists (select 1 from public.private_settings
              where key = 'daily_drop_sent' and value = v_day::text) then
    return 0;
  end if;

  select w.window_key into v_window
    from public.current_prompt_window((p_at at time zone 'Asia/Kolkata')) w;

  select count(*)::int into v_dips from public.posts p
   where p.visibility = 'anonymous' and p.deleted_at is null
     and ((p.created_at at time zone 'UTC') at time zone 'Asia/Kolkata')::date = v_day;

  perform set_config('app.notif_trusted', 'on', true);
  with mine as (
    select u.id as user_id, c.id as community_id,
           row_number() over (partition by u.id
             order by case when v_window is null then 0
                           else public.window_affinity_for(c.id, v_window) end desc,
                      cm.joined_at) as pick
      from public.users u
      join public.community_members cm on cm.user_id = u.auth_id
      join public.communities c on c.id = cm.community_id and c.deleted_at is null
     where u.deleted_at is null and u.auth_id is not null
  ),
  chosen as (select user_id, community_id from mine where pick = 1),
  resolved as (
    select ch.user_id, ch.community_id,
           case when v_window is null then null
                else public.pick_window_prompt(ch.community_id, v_window, v_day, 'anon') end as pid
      from chosen ch
  ),
  final as (
    select r.user_id, r.community_id, r.pid, dp.prompt_text,
           (row_number() over (order by r.user_id) - 1) as seq
      from resolved r left join public.daily_prompts dp on dp.id = r.pid
  )
  insert into public.notifications
    (recipient_id, type, tier, title, body, data, dedupe_key, push_after)
  select f.user_id, 'daily_drop', 'major',
         '⚡ It''s Dip time',
         coalesce(case when length(f.prompt_text) > 80
                       then left(f.prompt_text, 79) || '…' else f.prompt_text end
                  || ' — ', '')
         || case when v_dips > 0 then v_dips || ' already answered. Nobody will know it''s you 🤫'
                 else 'Be the first. Nobody will know it''s you 🤫' end,
         jsonb_strip_nulls(jsonb_build_object(
           'screen', 'composer', 'feed_scope', 'anon',
           'prefill_prompt', f.prompt_text,
           'community_id', f.community_id,
           'prompt_id', f.pid)),
         'daily_drop:' || f.user_id::text || ':' || v_day::text,
         p_at + ((f.seq / c_batch) * c_stagger)
    from final f
  on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics n = row_count;
  perform set_config('app.notif_trusted', 'off', true);

  insert into public.private_settings(key, value) values ('daily_drop_sent', v_day::text)
  on conflict (key) do update set value = excluded.value;
  return n;
end $$;
revoke all on function public.notify_daily_drop(timestamptz) from public, anon, authenticated;

select cron.schedule('daily-drop', '*/5 * * * *', 'SELECT public.notify_daily_drop();');

-- ── 2. reaction batching ──────────────────────────────────────────────────
create or replace function public.fold_reaction_notification(p_owner uuid, p_post uuid, p_actor uuid, p_emoji text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.notifications%rowtype;
  v_count  int;
  v_thing  text;
begin
  select case when p.visibility = 'anonymous' then 'Dip' else 'post' end
    into v_thing from public.posts p where p.id = p_post;
  v_thing := coalesce(v_thing, 'post');

  -- The running batch for this post: its latest reaction row from the last
  -- 24h, pushed or not.
  select * into v_row
    from public.notifications
   where recipient_id = p_owner and type = 'reaction'
     and post_id is not distinct from p_post
     and created_at > now() - interval '24 hours'
   order by created_at desc
   limit 1;

  if v_row.id is null then
    insert into public.notifications
      (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key, push_after)
    values (p_owner, 'reaction', p_actor, p_post, 'minor',
            'Someone reacted to your ' || v_thing || ' 👀', p_emoji,
            jsonb_build_object('reactor_count', 1,
                               'reactors', jsonb_build_object(p_actor::text, true),
                               'screen', 'post', 'post_id', p_post),
            'reaction_batch:' || p_post::text || ':' || extract(epoch from now())::bigint::text,
            -- Held briefly so the next few reactions fold into this push.
            now() + interval '15 minutes')
    on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
    return;
  end if;

  if v_row.data->'reactors' ? p_actor::text then return; end if;
  v_count := coalesce((v_row.data->>'reactor_count')::int, 1) + 1;

  perform set_config('app.notif_trusted', 'on', true);
  if v_row.push_sent_at is not null and v_count in (5, 10, 25, 50, 100, 250) then
    -- Milestone after the batch already went out: one fresh push.
    insert into public.notifications
      (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key, push_after)
    values (p_owner, 'reaction', null, p_post, 'minor',
            '🔥 ' || v_count || ' reactions on your ' || v_thing, p_emoji,
            coalesce(v_row.data, '{}'::jsonb)
              || jsonb_build_object('reactor_count', v_count)
              || jsonb_build_object('reactors',
                   coalesce(v_row.data->'reactors', '{}'::jsonb) || jsonb_build_object(p_actor::text, true)),
            'reaction_batch:' || p_post::text || ':m' || v_count,
            now())
    on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
  else
    update public.notifications
       set title = case when v_count >= 5
                        then '🔥 ' || v_count || ' reactions on your ' || v_thing
                        else v_count || ' people reacted to your ' || v_thing || ' 👀' end,
           actor_id = null,
           data  = coalesce(data, '{}'::jsonb)
                   || jsonb_build_object('reactor_count', v_count)
                   || jsonb_build_object('reactors',
                        coalesce(data->'reactors', '{}'::jsonb) || jsonb_build_object(p_actor::text, true))
     where id = v_row.id;
  end if;
  perform set_config('app.notif_trusted', 'off', true);
end $$;

-- ── 3. weekly recap ───────────────────────────────────────────────────────
create or replace function public.notify_weekly_recap(p_at timestamptz default now())
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_since_tz  timestamptz := p_at - interval '7 days';
  v_since_utc timestamp   := (p_at - interval '7 days') at time zone 'UTC';
  v_week text := to_char((p_at at time zone 'Asia/Kolkata')::date, 'IYYY-IW');
  n int := 0;
begin
  perform set_config('app.notif_trusted', 'on', true);
  with pv as (
    select distinct v.viewed_user_id as uid, v.viewer_id
      from public.profile_views v
     where v.created_at >= v_since_utc and v.viewer_id <> v.viewed_user_id
  ),
  dv as (
    select distinct p.user_id as uid, x.viewer_id
      from public.post_views x
      join public.posts p on p.id = x.post_id
     where p.visibility = 'anonymous' and p.deleted_at is null
       and x.created_at >= v_since_tz and x.viewer_id <> p.user_id
  ),
  vb as (
    select pv.uid, pv.viewer_id,
           upper((select db.branch from public.derive_branch(a.email) db)) as br
      from pv
      join public.users u on u.id = pv.viewer_id
      left join auth.users a on a.id = u.auth_id
  ),
  agg as (
    select u.id as uid,
           (select count(*) from vb where vb.uid = u.id)::int as n_prof,
           (select count(*) from dv where dv.uid = u.id)::int as n_dip,
           (select count(*) from vb join dv on dv.uid = vb.uid and dv.viewer_id = vb.viewer_id
             where vb.uid = u.id)::int as n_both,
           tb.br as top_br, coalesce(tb.c, 0)::int as top_c
      from public.users u
      left join lateral (
        select vb.br, count(*) as c from vb
         where vb.uid = u.id and vb.br is not null
         group by vb.br order by count(*) desc limit 1
      ) tb on true
     where u.deleted_at is null and u.auth_id is not null
  )
  insert into public.notifications
    (recipient_id, type, tier, title, body, data, dedupe_key, push_after)
  select a.uid, 'weekly_recap', 'minor',
         case
           when a.n_prof > 0 and a.top_br is not null and a.top_c = a.n_prof
             then '👀 ' || a.n_prof || case when a.n_prof = 1 then ' person' else ' people' end
                  || ' from ' || a.top_br || ' viewed your profile this week'
           when a.n_prof > 0 and a.top_br is not null
             then '👀 ' || a.n_prof || ' people viewed your profile this week — most from ' || a.top_br
           when a.n_prof > 0
             then '👀 ' || a.n_prof || case when a.n_prof = 1 then ' person' else ' people' end
                  || ' viewed your profile this week'
           else '👀 ' || a.n_dip || case when a.n_dip = 1 then ' person' else ' people' end
                  || ' saw your Dips this week'
         end,
         case
           when a.n_prof > 0 and a.n_both > 0
             then a.n_both || ' of them also saw your Dip. Pin your people to see who 📌'
           when a.n_prof > 0 and a.n_dip > 0
             then a.n_dip || ' people saw your Dips too. Pin your people to see who 📌'
           else 'Pin your people to see who 📌'
         end,
         jsonb_build_object('screen', 'profile'),
         'weekly_recap:' || a.uid::text || ':' || v_week,
         p_at
    from agg a
   where a.n_prof > 0 or a.n_dip > 0
  on conflict (type, dedupe_key) where dedupe_key is not null do nothing;
  get diagnostics n = row_count;
  perform set_config('app.notif_trusted', 'off', true);
  return n;
end $$;
revoke all on function public.notify_weekly_recap(timestamptz) from public, anon, authenticated;

-- Sunday 19:00 IST = 13:30 UTC.
select cron.schedule('weekly-recap', '30 13 * * 0', 'SELECT public.notify_weekly_recap();');

-- ── 4. streak freezes ─────────────────────────────────────────────────────
-- Pair ping streak: walk the reply days backwards. Today still being open
-- never breaks it; a single missed day is bridged at most once per ISO week.
create or replace function public.ping_streak_between(p_a uuid, p_b uuid)
returns integer
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_today  date := (now() at time zone 'Asia/Kolkata')::date;
  v_expect date;
  v_streak int := 0;
  v_frozen text[] := '{}';
  v_week   text;
  d        date;
begin
  for d in
    select distinct ((r.created_at at time zone 'UTC') at time zone 'Asia/Kolkata')::date as day
      from public.ping_replies r join public.pings p on p.id = r.ping_id
     where r.deleted_at is null
       and ((p.sender_id = p_a and p.receiver_id = p_b) or (p.sender_id = p_b and p.receiver_id = p_a))
     order by 1 desc
  loop
    if v_expect is null then
      -- Today not answered yet is fine: start from yesterday.
      v_expect := case when d = v_today then v_today else v_today - 1 end;
    end if;
    if d = v_expect then
      v_streak := v_streak + 1;
      v_expect := d - 1;
    elsif d = v_expect - 1 then
      v_week := to_char(v_expect, 'IYYY-IW');
      exit when v_week = any(v_frozen);
      v_frozen := v_frozen || v_week;       -- 🧊 freeze covers v_expect
      v_streak := v_streak + 1;
      v_expect := d - 1;
    else
      exit;
    end if;
  end loop;
  return v_streak;
end $$;

create or replace function public.ping_streak_with(p_other uuid)
returns integer
language sql stable security definer
set search_path = public, pg_temp
as $$
  select public.ping_streak_between(public.current_user_id(), p_other);
$$;

-- Group ping streak: a failed day is bridged once per 7 days.
alter table public.group_ping_streaks add column if not exists freeze_used_on date;

create or replace function public.resolve_group_ping_day(p_date date)
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  d             record;
  v_replied     uuid[];
  v_all_replied boolean;
  v_freeze      boolean;
  n             int := 0;
begin
  for d in select * from public.group_ping_days
            where on_date = p_date and not resolved loop

    select coalesce(array_agg(distinct r.replier_id), '{}')
      into v_replied
      from public.ping_replies r
      join public.pings p on p.id = r.ping_id
     where p.thread_id = d.thread_id;

    select bool_and(m = any(v_replied)) into v_all_replied
      from unnest(d.member_ids) m;
    v_all_replied := coalesce(v_all_replied, false);

    -- 🧊 A live streak that misses today keeps going if its weekly freeze
    -- is unused — the day counts as bridged, not as a completed day.
    select not v_all_replied
           and coalesce(gs.current_streak, 0) > 0
           and gs.last_complete_on = p_date - 1
           and (gs.freeze_used_on is null or gs.freeze_used_on <= p_date - 7)
      into v_freeze
      from public.group_ping_streaks gs where gs.group_id = d.group_id;
    v_freeze := coalesce(v_freeze, false);

    insert into public.group_ping_streaks as gs
      (group_id, current_streak, longest_streak, last_complete_on)
    values (
      d.group_id,
      case when v_all_replied then 1 else 0 end,
      case when v_all_replied then 1 else 0 end,
      case when v_all_replied then p_date end
    )
    on conflict (group_id) do update set
      current_streak = case
        when v_freeze then gs.current_streak
        when not v_all_replied then 0
        when gs.last_complete_on = p_date - 1 then gs.current_streak + 1
        else 1 end,
      longest_streak = greatest(gs.longest_streak, case
        when v_freeze then gs.current_streak
        when not v_all_replied then 0
        when gs.last_complete_on = p_date - 1 then gs.current_streak + 1
        else 1 end),
      last_complete_on = case when v_all_replied or v_freeze then p_date
                              else gs.last_complete_on end,
      freeze_used_on = case when v_freeze then p_date else gs.freeze_used_on end,
      updated_at = now();

    insert into public.group_ping_member_streaks as ms
      (group_id, user_id, current_streak, longest_streak, last_reply_on)
    select d.group_id, m, 1, 1, p_date
      from unnest(d.member_ids) m
     where m = any(v_replied)
    on conflict (group_id, user_id) do update set
      current_streak = case when ms.last_reply_on = p_date - 1
                            then ms.current_streak + 1 else 1 end,
      longest_streak = greatest(ms.longest_streak,
                        case when ms.last_reply_on = p_date - 1
                             then ms.current_streak + 1 else 1 end),
      last_reply_on = p_date,
      updated_at = now();

    update public.group_ping_member_streaks
       set current_streak = 0, updated_at = now()
     where group_id = d.group_id
       and user_id = any(d.member_ids)
       and not (user_id = any(v_replied));

    update public.group_ping_days set resolved = true
     where group_id = d.group_id and on_date = p_date;

    n := n + 1;
  end loop;
  return n;
end $$;
