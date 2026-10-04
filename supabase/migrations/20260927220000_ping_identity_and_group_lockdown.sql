-- Ping identity rules + group-ping lockdown (2026-09-27).
--
-- User ask:
--   * pinging from the Dip feed -> you appear under your ANON NAME;
--   * pinging from the Friends feed -> under your REAL NAME;
--   * pinging a Duo post -> goes separately to both partners, each replies
--     like a normal ping, and each is told it came from their Duo post;
--   * nobody but a group's members can ping the group, with no loopholes.
--
-- 1. LOOPHOLE CLOSED: pings had a client INSERT policy (sender = me, anything
--    else free), so anyone could write ping rows straight into any group or
--    at anyone, skipping send_group_ping's membership check and send_ping's
--    block / one-open-ping rules. No client inserts directly (every send is a
--    SECURITY DEFINER RPC, which bypasses RLS), so client INSERT is removed
--    entirely on pings and ping_threads.
-- 2. ping_post_author: identity now follows the POST, not a client flag.
--    An anonymous (Dip) post -> anonymous ping; any other post -> real name.
--    Both Friends-feed cards were passing anonymous: true, so those pings
--    were anonymous until now. receiver_hidden also follows the post: only a
--    Dip author stays masked from the sender (a Duo pair is known).
-- 3. Anonymous pings carry the sender's own anon name (users.anon_name)
--    instead of a random handle, 1:1 and group alike. ping_inbox shows their
--    anon avatar alongside it.
-- 4. notify_ping says where the ping came from ("... pinged you from your Duo
--    post 💞", "... about your Dip 👀"). ping_post_author passes the post via a
--    transaction-local setting, because source_post_id is written after the
--    ping row (and so after its notification) is inserted.

-- 1 -------------------------------------------------------------------------
DROP POLICY IF EXISTS pings_insert ON public.pings;
DROP POLICY IF EXISTS pings_block_filter_insert ON public.pings;
REVOKE INSERT ON public.pings FROM anon, authenticated;
REVOKE INSERT ON public.ping_threads FROM anon, authenticated;

-- 3 -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_ping_anon_label(p_me uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE((SELECT NULLIF(btrim(anon_name), '') FROM public.users WHERE id = p_me),
                  public.gen_handle());
$function$;
REVOKE EXECUTE ON FUNCTION public.my_ping_anon_label(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.send_ping(p_receiver_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    v_label := public.my_ping_anon_label(v_me);
  end if;

  insert into public.ping_threads (sender_id, kind, prompt, anonymous, anon_display_name, window_hours, photo_url)
  values (v_me, 'person', p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  returning id into v_thread;

  -- award_ping_sent_score (trigger on this insert) is the ONLY source of the
  -- +25 ping_score award.
  insert into public.pings (thread_id, sender_id, receiver_id, prompt, anonymous, window_hours, photo_url)
  values (v_thread, v_me, p_receiver_id, p_prompt, p_anonymous, p_window_hours, p_photo_url);

  return v_thread;
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_group_ping(p_group_id uuid, p_prompt text, p_anonymous boolean DEFAULT false, p_window_hours integer DEFAULT 5, p_photo_url text DEFAULT NULL::text)
 RETURNS TABLE(thread_id uuid, recipients integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- A group only you have joined can't be pinged: invitees are pinged once
  -- they ACCEPT, not before.
  IF NOT EXISTS (SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = p_group_id AND gm.user_id <> v_me) THEN
    RAISE EXCEPTION 'Waiting for members to join this group.';
  END IF;

  IF p_anonymous THEN
    v_label := public.my_ping_anon_label(v_me);
  END IF;

  INSERT INTO public.ping_threads (sender_id, kind, group_id, prompt, anonymous, anon_display_name, window_hours, photo_url)
  VALUES (v_me, 'group', p_group_id, p_prompt, p_anonymous, v_label, p_window_hours, p_photo_url)
  RETURNING id INTO v_thread;

  INSERT INTO public.pings (thread_id, sender_id, receiver_id, group_id, prompt, anonymous, window_hours, photo_url)
  SELECT v_thread, v_me, gm.user_id, p_group_id, p_prompt, p_anonymous, p_window_hours, p_photo_url
    FROM public.group_members gm
   WHERE gm.group_id = p_group_id
     AND NOT public.is_blocked_user(auth.uid(), gm.user_id);

  SELECT count(*) INTO v_n
    FROM public.pings pp WHERE pp.thread_id = v_thread AND pp.receiver_id <> v_me;

  IF v_n = 0 THEN
    DELETE FROM public.ping_threads WHERE id = v_thread;
    DELETE FROM public.pings WHERE pings.thread_id = v_thread;
    RETURN QUERY SELECT NULL::UUID, 0;
    RETURN;
  END IF;

  UPDATE public.users SET ping_score = ping_score + 25 WHERE id = v_me;
  PERFORM public.log_score_event(v_me, 'ping_sent', 25);
  PERFORM public.open_group_ping_day(p_group_id, v_thread);

  RETURN QUERY SELECT v_thread, v_n;
END;
$function$;

-- 2 -------------------------------------------------------------------------
-- p_anonymous is kept in the signature for existing clients but IGNORED:
-- identity follows the post.
CREATE OR REPLACE FUNCTION public.ping_post_author(p_post_id uuid, p_prompt text, p_anonymous boolean DEFAULT true, p_window_hours integer DEFAULT 5)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me      uuid;
  v_target  uuid;
  v_partner uuid;
  v_vis     text;
  v_anon    boolean;
  v_thread  uuid;
  v_first   uuid;
begin
  select u.id into v_me from public.users u where u.auth_id = auth.uid();

  select p.user_id, p.partner_user_id, p.visibility into v_target, v_partner, v_vis
    from public.posts p
   where p.id = p_post_id and p.deleted_at is null;
  if v_target is null then
    raise exception 'Post not found.';
  end if;

  -- Dip post -> anon name; anything else (Friends feed, Duo) -> real name.
  v_anon := (v_vis = 'anonymous');

  -- Read by notify_ping (the notification fires on the ping insert, before
  -- source_post_id is written below).
  perform set_config('app.ping_source_post', p_post_id::text, true);

  if v_target is distinct from v_me then
    v_thread := public.send_ping(v_target, p_prompt, v_anon, p_window_hours);
    update public.pings
       set receiver_hidden = v_anon, source_post_id = p_post_id
     where thread_id = v_thread;
    v_first := v_thread;
  end if;

  -- Duo post: a separate ping to the partner, answered like any other.
  if v_partner is not null and v_partner is distinct from v_target
     and v_partner is distinct from v_me then
    v_thread := public.send_ping(v_partner, p_prompt, v_anon, p_window_hours);
    update public.pings
       set receiver_hidden = v_anon, source_post_id = p_post_id
     where thread_id = v_thread;
    v_first := coalesce(v_first, v_thread);
  end if;

  perform set_config('app.ping_source_post', '', true);

  if v_first is null then
    if v_target = v_me and (v_partner is null or v_partner = v_me) then
      raise exception 'You cannot ping yourself.';
    end if;
    raise exception 'No one to ping on this post.';
  end if;

  return v_first;
end;
$function$;

-- 4 -------------------------------------------------------------------------
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
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your Dip 👀'
    WHEN v_src IS NOT NULL
      THEN COALESCE(v_who, 'Someone') || ' pinged you about your post 💭'
    WHEN NEW.anonymous IS TRUE
      THEN COALESCE(v_who, 'Someone') || ' is thinking about you 👀'
    ELSE COALESCE(v_who, 'Someone') || ' pinged you 💭'
  END;

  INSERT INTO public.notifications (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
  VALUES (NEW.receiver_id, 'ping',
          CASE WHEN NEW.anonymous IS TRUE THEN NULL ELSE NEW.sender_id END,
          'major', v_title, NEW.prompt,
          jsonb_build_object('screen','ping','ping_id', NEW.id, 'source_post_id', v_src),
          'ping:' || NEW.id::text)
  ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

  RETURN NEW;
END;
$function$;

-- 3 (inbox avatar) ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ping_inbox()
 RETURNS TABLE(ping_id uuid, thread_id uuid, kind text, prompt text, created_at timestamp without time zone, window_hours integer, status text, anonymous boolean, group_id uuid, group_name text, group_size integer, sender_id uuid, sender_name text, sender_avatar text, expires_at timestamp with time zone, photo_url text, seen_at timestamp without time zone, photo_opened_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select
    p.id, p.thread_id, t.kind, p.prompt, p.created_at, p.window_hours,
    p.status, p.anonymous,
    p.group_id,
    g.name,
    (select count(*)::int from public.group_members gm where gm.group_id = p.group_id),
    case when p.anonymous then null else p.sender_id end,
    case when p.anonymous then t.anon_display_name else u.name end,
    -- Anonymous: the sender's anon persona avatar, never their real photo.
    case when p.anonymous then u.anon_photo_url else u.profile_photo_url end,
    p.expires_at,
    p.photo_url,
    p.seen_at,
    p.photo_opened_at
  from public.pings p
  join public.ping_threads t on t.id = p.thread_id
  left join public.users u on u.id = p.sender_id
  left join public.groups g on g.id = p.group_id
  where p.receiver_id = public.current_user_id()
    and p.sender_id <> p.receiver_id
    and p.expires_at > now()
    and (p.group_id is not null or not public.is_blocked_user(auth.uid(), p.sender_id))
  order by p.created_at desc;
$function$;
