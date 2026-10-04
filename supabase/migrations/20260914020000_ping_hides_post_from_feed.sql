-- ---------------------------------------------------------------------------
-- Feed: hide a post once you've pinged its author.
--
-- Explicit request: "once they react or ping the post, that post shall not
-- be shown in the feed to them again." The "react" half already worked —
-- FeedService.reactedPostIds() covers both reaction tables. Ping had no
-- link back to the post it was sent FROM at all: `pings` carries a
-- `thread_id`/sender/receiver, never the post that prompted it, so there
-- was nothing for a feed query to exclude on.
--
-- `ping_post_author(p_post_id, ...)` (the RPC the feed's own ping button
-- calls) already receives p_post_id — this just has it write that down.
-- ---------------------------------------------------------------------------

ALTER TABLE public.pings
  ADD COLUMN IF NOT EXISTS source_post_id uuid REFERENCES public.posts(id);

-- Read-heavy, keyed the way FeedService.pingedPostIds() below queries it.
CREATE INDEX IF NOT EXISTS pings_sender_source_post_idx
  ON public.pings (sender_id, source_post_id)
  WHERE source_post_id IS NOT NULL;

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
    raise exception 'No one to ping on this post.';
  end if;

  return v_first;
end;
$function$;
