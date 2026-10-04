-- A Duo post pinged BOTH authors in one call, and one blocked author made
-- send_ping raise and roll back the whole ping (found 2026-09-30: pinging a
-- Duo post with someone who had blocked the pinger failed outright). Now a
-- blocked author is simply skipped; only when nobody on the post can be
-- pinged does it raise, with send_ping's own 'Cannot ping this user.'.
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

  v_anon := (v_vis = 'anonymous');

  perform set_config('app.ping_source_post', p_post_id::text, true);

  if v_target is distinct from v_me
     and not public.is_blocked_user(auth.uid(), v_target) then
    v_thread := public.send_ping(v_target, p_prompt, v_anon, p_window_hours);
    update public.pings
       set receiver_hidden = v_anon, source_post_id = p_post_id
     where thread_id = v_thread;
    v_first := v_thread;
  end if;

  if v_partner is not null and v_partner is distinct from v_target
     and v_partner is distinct from v_me
     and not public.is_blocked_user(auth.uid(), v_partner) then
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
    -- Everyone on the post is blocked (either direction) — same wording
    -- send_ping uses, which the app maps to PingBlocked.
    raise exception 'Cannot ping this user.';
  end if;

  return v_first;
end;
$function$;
