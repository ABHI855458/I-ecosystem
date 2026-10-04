-- Pinging your own post (anon or friends feed) fell through to the generic
-- "No one to ping on this post" — technically true (send_ping was never
-- called) but misleading, since the real reason is a deliberate self-ping
-- block, not an empty/authorless post. Explicit request: "let the message
-- come like you cannot ping yourself".
CREATE OR REPLACE FUNCTION public.ping_post_author(p_post_id uuid, p_prompt text, p_anonymous boolean DEFAULT true, p_window_hours integer DEFAULT 5)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me      uuid;
  v_target  uuid;
  v_partner uuid;
  v_thread  uuid;
  v_first   uuid;
begin
  select u.id into v_me from public.users u where u.auth_id = auth.uid();

  select p.user_id, p.partner_user_id into v_target, v_partner
    from public.posts p
   where p.id = p_post_id and p.deleted_at is null;
  if v_target is null then
    raise exception 'Post not found.';
  end if;

  if v_target is distinct from v_me then
    v_thread := public.send_ping(v_target, p_prompt, p_anonymous, p_window_hours);
    update public.pings
       set receiver_hidden = true, source_post_id = p_post_id
     where thread_id = v_thread;
    v_first := v_thread;
  end if;

  if v_partner is not null and v_partner is distinct from v_target
     and v_partner is distinct from v_me then
    v_thread := public.send_ping(v_partner, p_prompt, p_anonymous, p_window_hours);
    update public.pings
       set receiver_hidden = true, source_post_id = p_post_id
     where thread_id = v_thread;
    v_first := coalesce(v_first, v_thread);
  end if;

  if v_first is null then
    if v_target = v_me and (v_partner is null or v_partner = v_me) then
      raise exception 'You cannot ping yourself.';
    end if;
    raise exception 'No one to ping on this post.';
  end if;

  return v_first;
end;
$function$;
