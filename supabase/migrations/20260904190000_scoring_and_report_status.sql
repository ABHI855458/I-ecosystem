-- Wires the two score displays (Ping page's "Ping Score", Anon tab's
-- "Anon Score" badge, and both mirrored on Profile) to real actions instead
-- of the in-memory fake counters they read today, and closes the reporter
-- feedback loop (reports had no status/resolution and nothing was ever
-- written back to the person who reported something).
--
-- users.ping_score / users.glow_score already exist live, already 0 for
-- every row, and Profile (my_profile_screen.dart, their_profile_screen.dart
-- via profile_lookup_service.dart) already reads them correctly — this
-- migration is entirely about making them real, not adding new columns for
-- the score values themselves. "glow_score" is this table's existing name
-- for what the app's UI calls Anon Score.

-- ---------------------------------------------------------------------------
-- PING SCORE: +25 for sending a ping (person or group, once per send call,
-- not per recipient), +20 for sending a reply.
-- ---------------------------------------------------------------------------

create or replace function public.send_ping(p_receiver_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_receiver_id = v_me THEN RAISE EXCEPTION 'Cannot ping yourself.'; END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours)
  VALUES (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours);

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;

  RETURN v_thread;
END;
$function$;

create or replace function public.send_group_ping(p_group_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5)
 returns table(thread_id uuid, recipients integer)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
DECLARE
  v_me UUID;
  v_thread UUID;
  v_label TEXT;
  v_n INT;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.is_group_member(p_group_id, v_me) THEN
    RAISE EXCEPTION 'Not a member of that group.';
  END IF;

  IF p_anonymous THEN
    v_label := public.gen_handle();
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours
    FROM public.group_members gm
   WHERE gm.group_id = p_group_id
     AND (p_anonymous OR gm.user_id <> v_me);

  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$;

create or replace function public.award_ping_reply_score()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.users set ping_score = ping_score + 20 where id = new.replier_id;
  return new;
end;
$$;

create trigger trg_award_ping_reply_score
  after insert on public.ping_replies
  for each row execute function public.award_ping_reply_score();

-- ---------------------------------------------------------------------------
-- ANON SCORE (glow_score): +25 for making an anon post, +5 to the author
-- whenever someone comments, reacts, or (first-time) views that post.
-- All three engagement triggers explicitly skip the author reacting/
-- commenting/viewing their own post, and skip non-anonymous posts entirely
-- — this is an anon-feed-only score, matching the spec.
-- ---------------------------------------------------------------------------

create or replace function public.award_anon_post_score()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.users set glow_score = glow_score + 25 where id = new.user_id;
  return new;
end;
$$;

create trigger trg_award_anon_post_score
  after insert on public.posts
  for each row
  when (new.visibility = 'anonymous')
  execute function public.award_anon_post_score();

create or replace function public.award_anon_engagement_score()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
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
  return new;
end;
$$;

create trigger trg_award_anon_engagement_comments
  after insert on public.comments
  for each row
  when (new.post_id is not null)
  execute function public.award_anon_engagement_score();

create trigger trg_award_anon_engagement_reactions
  after insert on public.reactions
  for each row
  when (new.post_id is not null)
  execute function public.award_anon_engagement_score();

create trigger trg_award_anon_engagement_realmoji
  after insert on public.post_realmoji_reactions
  for each row
  when (new.post_id is not null)
  execute function public.award_anon_engagement_score();

-- View tracking never existed at all — posts.view_count sat unused (0 on
-- every row, no writer anywhere). A dedup junction table is required rather
-- than a bare increment: without it, a viewer re-scrolling past the same
-- anon post repeatedly could inflate the author's score without limit.
create table if not exists public.post_views (
  post_id uuid not null references public.posts(id) on delete cascade,
  viewer_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, viewer_id)
);

alter table public.post_views enable row level security;

create policy post_views_insert_self on public.post_views
  for insert
  with check (viewer_id in (select id from public.users where auth_id = auth.uid()));

create policy post_views_select_self on public.post_views
  for select
  using (viewer_id in (select id from public.users where auth_id = auth.uid()));

-- SECURITY DEFINER so the +5 credit to the post's author (a different row
-- than the viewer) doesn't need its own RLS grant — same mechanism already
-- used by send_ping/send_group_ping for the sender-side score bump above.
create or replace function public.record_post_view(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me uuid;
  v_owner uuid;
  v_vis text;
  v_n int;
begin
  v_me := public.current_user_id();
  if v_me is null then
    return;
  end if;

  select user_id, visibility into v_owner, v_vis from public.posts where id = p_post_id;
  if v_owner is null or v_owner = v_me or v_vis is distinct from 'anonymous' then
    return;
  end if;

  insert into public.post_views (post_id, viewer_id)
  values (p_post_id, v_me)
  on conflict (post_id, viewer_id) do nothing;

  get diagnostics v_n = row_count;
  if v_n > 0 then
    update public.users set glow_score = glow_score + 5 where id = v_owner;
    update public.posts set view_count = coalesce(view_count, 0) + 1 where id = p_post_id;
  end if;
end;
$function$;

grant execute on function public.record_post_view(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- REPORT FEEDBACK LOOP: reports had no status/resolution and nothing was
-- ever written back to the reporter (RLS gives them no read access to
-- `reports` at all, correctly — they aren't meant to see the moderation
-- queue). Closing the loop through the existing notifications feed instead:
-- the dashboard, on Remove/Dismiss, updates the report's status and inserts
-- a notification the reporter's own app already knows how to render.
-- ---------------------------------------------------------------------------

alter table public.reports
  add column if not exists status text not null default 'pending' check (status in ('pending', 'removed', 'dismissed')),
  add column if not exists resolved_at timestamptz;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type = any (array['reaction'::text, 'ping'::text, 'friend_request'::text, 'friend_accepted'::text, 'branch_view'::text, 'us_album_mutual'::text, 'report_resolved'::text]));
