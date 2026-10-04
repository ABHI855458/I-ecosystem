-- Likes on MY ping replies, shown where I replied (2026-09-27).
--
-- User ask: when the ping's sender likes my reply, show it on my "📷 Photo
-- sent" receipt row, and tell me who liked it.
--
-- 1. ping_inbox() gains my_replies: my replies to each inbound ping, oldest
--    first, each with its like count. The receipt rows used to live only in
--    the app's memory (lost on restart, and never knew about likes).
-- 2. toggle_ping_reply_reaction's notification names the liker: "Abhi liked
--    your reply ❤️" — the ping's anon name when the ping was anonymous, so a
--    like never unmasks an anonymous sender.

DROP FUNCTION IF EXISTS public.ping_inbox();
CREATE FUNCTION public.ping_inbox()
 RETURNS TABLE(ping_id uuid, thread_id uuid, kind text, prompt text, created_at timestamp without time zone, window_hours integer, status text, anonymous boolean, group_id uuid, group_name text, group_size integer, sender_id uuid, sender_name text, sender_avatar text, expires_at timestamp with time zone, photo_url text, seen_at timestamp without time zone, photo_opened_at timestamp with time zone, my_replies jsonb)
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
    case when p.anonymous then u.anon_photo_url else u.profile_photo_url end,
    p.expires_at,
    p.photo_url,
    p.seen_at,
    p.photo_opened_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', r.kind,
               'body', r.body,
               'likes', (select count(*) from public.ping_reply_reactions rr where rr.reply_id = r.id))
             order by r.created_at)
        from public.ping_replies r
       where r.ping_id = p.id
         and r.replier_id = public.current_user_id()
         and r.deleted_at is null
    ), '[]'::jsonb)
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
REVOKE EXECUTE ON FUNCTION public.ping_inbox() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ping_inbox() TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_ping_reply_reaction(p_reply_id uuid)
 RETURNS TABLE(liked boolean, reaction_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me       uuid;
  v_sender   uuid;
  v_replier  uuid;
  v_ping_id  uuid;
  v_group    uuid;
  v_thread   uuid;
  v_photo    text;
  v_anon     boolean;
  v_who      text;
  v_existed  boolean;
BEGIN
  SELECT id INTO v_me FROM public.users WHERE auth_id = auth.uid();
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  SELECT p.sender_id, r.replier_id, r.ping_id, p.group_id, p.thread_id, r.photo_url, p.anonymous
    INTO v_sender, v_replier, v_ping_id, v_group, v_thread, v_photo, v_anon
  FROM public.ping_replies r
  JOIN public.pings p ON p.id = r.ping_id
  WHERE r.id = p_reply_id AND r.deleted_at IS NULL;

  IF v_ping_id IS NULL THEN
    RAISE EXCEPTION 'reply not found';
  END IF;

  IF v_group IS NULL THEN
    IF v_sender IS DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'only the ping sender can react to this reply';
    END IF;
  ELSE
    IF v_replier IS NOT DISTINCT FROM v_me THEN
      RAISE EXCEPTION 'cannot react to your own reply';
    END IF;
    IF NOT public.has_answered_thread(v_thread, v_me) THEN
      RAISE EXCEPTION 'answer this wall before reacting to it';
    END IF;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me
  ) INTO v_existed;

  IF v_existed THEN
    DELETE FROM public.ping_reply_reactions
     WHERE reply_id = p_reply_id AND reactor_id = v_me;
  ELSE
    INSERT INTO public.ping_reply_reactions (reply_id, reactor_id)
    VALUES (p_reply_id, v_me)
    ON CONFLICT (reply_id, reactor_id) DO NOTHING;

    IF v_replier IS DISTINCT FROM v_me THEN
      -- Who liked it. An anonymous 1:1 sender stays masked: their ping's
      -- anon name, never their real name.
      IF v_group IS NULL AND v_anon IS TRUE THEN
        SELECT NULLIF(btrim(anon_display_name), '') INTO v_who
          FROM public.ping_threads WHERE id = v_thread;
      ELSE
        SELECT COALESCE(NULLIF(btrim(name), ''), anon_name) INTO v_who
          FROM public.users WHERE id = v_me;
      END IF;

      INSERT INTO public.notifications
        (recipient_id, type, actor_id, tier, title, body, data, dedupe_key)
      VALUES (v_replier, 'ping_reply_liked',
              CASE WHEN v_group IS NULL AND v_anon IS TRUE THEN NULL ELSE v_me END,
              'minor',
              COALESCE(v_who, 'Someone') || ' liked your '
                || CASE WHEN v_photo IS NULL THEN 'reply' ELSE 'photo' END || ' ❤️',
              NULL,
              jsonb_build_object('screen','ping_reveal','ping_id', v_ping_id, 'ping_reply_id', p_reply_id),
              'ping_reply_liked:' || p_reply_id::text || ':' || v_me::text)
      ON CONFLICT (type, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;

  RETURN QUERY
  SELECT (NOT v_existed),
         (SELECT count(*)::int FROM public.ping_reply_reactions WHERE reply_id = p_reply_id);
END;
$function$;
