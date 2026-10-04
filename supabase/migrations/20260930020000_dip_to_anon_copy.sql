-- Rename the anonymous feed's user-facing name from "Dip" to "Anon"
-- everywhere it appears in push/notification copy. Client-side rename
-- (toggle chip label, score reward label) is a separate app change.

CREATE OR REPLACE FUNCTION public.notify_ping()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_who text; v_src uuid; v_src_type text; v_src_vis text; v_title text;
BEGIN
  IF NEW.receiver_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sender_id = NEW.receiver_id THEN RETURN NEW; END IF;

  IF NEW.anonymous IS TRUE THEN
    SELECT NULLIF(btrim(t.anon_display_name), '') INTO v_who
      FROM public.ping_threads t WHERE t.id = NEW.thread_id;
  ELSE
    SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
      FROM public.users WHERE id = NEW.sender_id;
  END IF;

  BEGIN
    v_src := NULLIF(current_setting('app.ping_source_post', true), '')::uuid;
  EXCEPTION WHEN others THEN
    v_src := NULL;
  END;
  IF v_src IS NOT NULL THEN
    SELECT post_type, visibility INTO v_src_type, v_src_vis
      FROM public.posts WHERE id = v_src;
  END IF;

  v_title := CASE
    WHEN v_src_type = 'us'
      THEN COALESCE(v_who, 'Someone') || ' pinged you from your Duo post 💞'
    WHEN v_src_vis = 'anonymous'
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your Anon 👀'
    WHEN v_src IS NOT NULL
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your post 💭'
    WHEN NEW.anonymous IS TRUE
      THEN COALESCE(v_who, 'Someone') || ' is thinking about you 👀'
    ELSE COALESCE(v_who, 'Someone') || ' pinged you 💭'
  END;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major', v_title,
          -- A promptless ping (Friends feed / Ping page) has prompt '' —
          -- no body at all rather than an empty one.
          NULLIF(btrim(NEW.prompt), ''),
          jsonb_build_object('screen','ping','ping_id', NEW.id, 'source_post_id', v_src),
          'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_daily_drop(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
         '⚡ It''s Anon time',
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
end $function$;

CREATE OR REPLACE FUNCTION public.fold_reaction_notification(p_owner uuid, p_post uuid, p_actor uuid, p_emoji text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row    public.notifications%rowtype;
  v_count  int;
  v_thing  text;
begin
  select case when p.visibility = 'anonymous' then 'Anon' else 'post' end
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
end $function$;

CREATE OR REPLACE FUNCTION public.notify_weekly_recap(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                  || ' saw your Anons this week'
         end,
         case
           when a.n_prof > 0 and a.n_both > 0
             then a.n_both || ' of them also saw your Anon. Pin your people to see who 📌'
           when a.n_prof > 0 and a.n_dip > 0
             then a.n_dip || ' people saw your Anons too. Pin your people to see who 📌'
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
end $function$;

CREATE OR REPLACE FUNCTION public.notify_pinned_post_view()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_owner uuid; v_vis text; v_kind text;
  v_title text; v_screen text; v_day text;
BEGIN
  SELECT user_id, visibility, post_type INTO v_owner, v_vis, v_kind
  FROM public.posts WHERE id = NEW.post_id AND deleted_at IS NULL;

  IF v_owner IS NULL OR v_owner = NEW.viewer_id THEN RETURN NEW; END IF;

  IF NOT COALESCE(public.is_pinned_by(v_owner, NEW.viewer_id), false) THEN
    RETURN NEW;
  END IF;

  -- Surface naming, §6.7B. Anonymous is checked FIRST: an anon post is a
  -- Dip regardless of its post_type, and §6.5 requires anon-post copy to
  -- say "Dip" with no group name present, which is exactly this row's
  -- shape (a personal post has no group anywhere in it).
  IF v_vis = 'anonymous' THEN
    v_title  := 'Someone you pinned saw your Anon 👀';
    v_screen := 'post';
  ELSIF v_kind = 'moment' THEN
    v_title  := 'Someone you pinned saw your Moment 👀';
    v_screen := 'moment';
  ELSE
    v_title  := 'Someone you pinned saw your post 👀';
    v_screen := 'post';
  END IF;

  v_day := ((now() AT TIME ZONE 'Asia/Kolkata')::date)::text;

  PERFORM set_config('app.notif_trusted', 'on', true);
  INSERT INTO public.notifications
    (recipient_id, type, actor_id, post_id, tier, title, body, data, dedupe_key)
  VALUES (v_owner, 'pinned_post_view',
          NULL,                      -- privacy fix: never the viewer
          NEW.post_id, 'standard', v_title, NULL,
          jsonb_build_object('screen', v_screen, 'post_id', NEW.post_id),
          'pinned_post_view:' || NEW.post_id::text || ':' || v_day)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
  PERFORM set_config('app.notif_trusted', 'off', true);

  RETURN NEW;
END;
$function$;

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
              'Drop your first Anon — takes 10 seconds.',
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
      WHEN 'album'  THEN 'Got someone you''re close with? Start a Duo — it''s just the two of you.'
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
