-- `users.daily_streak` is documented and displayed everywhere as "the
-- poster's RED personal ANON streak" (feed_service.dart, design_solo_
-- card.dart) but was being bumped by three unrelated actions: an anon
-- post, a ping send, and a Moment post. A ping-only user (never touching
-- the anon feed) showed a growing red flame that every label in the app
-- describes as anon engagement specifically — scope leak, not intended
-- design, per explicit correction. The blue per-person/group streak
-- system already exists as the real mechanism for ping-driven engagement
-- (my_ping_streaks/group_ping_streak) — red should track anon posting
-- and nothing else.
--
-- Read-only on historical data: every existing user's current
-- daily_streak/daily_streak_last value is untouched by this migration.
-- Only FUTURE bumps change — a ping-only user's streak simply stops
-- growing from here; an anon-post-only user is completely unaffected,
-- since award_anon_post_score (below) is the one caller left untouched.

-- 1. award_ping_sent_score — drop the bump_daily_streak call. Ping's own
-- engagement signal is the blue streak system, not this one.
CREATE OR REPLACE FUNCTION public.award_ping_sent_score()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.group_id is not null then
    return new;
  end if;
  update public.users set ping_score = ping_score + 25 where id = new.sender_id;
  perform public.log_score_event(new.sender_id, 'ping_sent', 25);
  return new;
end;
$function$;

-- 2. award_moment_score — same, a Moment post is not an anon post (it can
-- be posted under a real name — see PostService's postType handling), so
-- it never belonged in the ANON streak either.
CREATE OR REPLACE FUNCTION public.award_moment_score()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE public.users SET glow_score = glow_score + 30 WHERE id = NEW.user_id;
  PERFORM public.log_score_event(NEW.user_id, 'moment_post', 30);
  RETURN NEW;
END;
$function$;

-- 3. send_ping — drop its OWN direct bump_daily_streak call, redundant
-- with (now-removed) award_ping_sent_score's. Harmless as it stood
-- (bump_daily_streak no-ops if already bumped today), but there is no
-- longer any reason for send_ping to touch the anon streak at all now
-- that ping sending isn't supposed to affect it in the first place.
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

  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours, p_photo_url);

  update public.users set ping_score = ping_score + 25 where id = v_me;

  return v_thread;
end;
$function$;
