-- ============================================================================
-- ping_post_author: a ping on a SHARED post reaches BOTH people.
--
-- A shared (Us Album) post has two authors — posts.user_id and
-- posts.partner_user_id. Pinging one of them and not the other makes the
-- second person invisible on a post that is half theirs: "if someone pings,
-- then ping shall go to both the people".
--
-- Returns the thread id of the FIRST ping sent, so the existing caller
-- contract is unchanged for ordinary single-author posts.
--
-- The pings are independent (two separate threads), which is deliberate: each
-- person answers on their own terms, and one of them replying must not close
-- the other's. It also means the per-person ping limit applies per person, as
-- it does everywhere else.
--
-- A self-ping is skipped rather than raising: if you ping a shared post you
-- are a co-author of, the OTHER person should still get it.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ping_post_author(
  p_post_id uuid,
  p_prompt text,
  p_anonymous boolean DEFAULT true,
  p_window_hours integer DEFAULT 5)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    update public.pings set receiver_hidden = true where thread_id = v_thread;
    v_first := v_thread;
  end if;

  if v_partner is not null and v_partner is distinct from v_target
     and v_partner is distinct from v_me then
    v_thread := public.send_ping(v_partner, p_prompt, p_anonymous, p_window_hours);
    update public.pings set receiver_hidden = true where thread_id = v_thread;
    v_first := coalesce(v_first, v_thread);
  end if;

  if v_first is null then
    raise exception 'No one to ping on this post.';
  end if;

  return v_first;
end;
$function$;
