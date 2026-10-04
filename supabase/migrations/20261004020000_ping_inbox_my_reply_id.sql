-- ============================================================================
-- ping_inbox().my_replies carries the reply id.
--
-- Reactions on a photo you SENT as a ping reply had nowhere to be seen: the
-- client knew your replies only as {kind, body, likes}, with no id to look
-- their reactions up by (reported 2026-10-04: "people aren't able to view the
-- reacted reactions to the photo sent via ping"). Adding 'id' lets the Ping
-- page show the reactor faces on your own reply. Nothing else changes.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.ping_inbox()
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
               'id', r.id,
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

COMMIT;
