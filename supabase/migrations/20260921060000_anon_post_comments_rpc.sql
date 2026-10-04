-- Restores anon-post comment BODIES after 20260921050000 locked the table.
--
-- WHY THIS EXISTS. 20260921050000 added the anonymous carve-out to
-- comments_select, which correctly stopped `comments.user_id` leaking the
-- real commenter behind an anonymous post. But it is a ROW-level policy, and
-- the leak was a COLUMN — so denying the row also hid the comment text,
-- which IS meant to be public on an anon post. Verified against the live
-- probe: comments_readable went 1 -> 0.
--
-- The fix is the pattern this codebase already uses for exactly this
-- problem: anon_post_reaction_faces(). The table denies direct reads; a
-- SECURITY DEFINER function serves precisely the sanitized projection that
-- is allowed. Same trust boundary, same search_path pinning, same
-- post_engagement_visible() gate.
--
-- WHAT IS DELIBERATELY NOT RETURNED: user_id and users.auth_id. Returning
-- auth_id is the separate client-side leak (fetchRecentAnon selected
-- `users(auth_id, ...)`, and `users` is readable, so the persona resolved to
-- a real account regardless of RLS). These functions make that impossible to
-- reintroduce by never putting the column in the result shape at all — which
-- is why the RLS fix and the client fix must ship together.
--
-- anon_name/anon_photo_url ARE returned: the persona is the whole point of
-- an anonymous thread, and neither maps back to an account.

CREATE OR REPLACE FUNCTION public.anon_post_comments(
  p_post_id uuid,
  p_limit   integer DEFAULT 20
)
RETURNS TABLE(
  id             uuid,
  content        text,
  created_at     timestamptz,
  anon_name      text,
  anon_photo_url text,
  thread_handle  text,
  is_mine        boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  select
    c.id,
    c.content,
    c.created_at,
    u.anon_name,
    u.anon_photo_url,
    -- Per-post pseudonym, resolved HERE rather than by handing the client
    -- an auth_id to look up. This is what removes the last need for the
    -- caller to ever see an identifier.
    h.handle,
    (u.auth_id = auth.uid()) as is_mine
  from public.comments c
  join public.users u on u.id = c.user_id
  left join public.post_thread_handles h
    on h.post_id = c.post_id and h.user_id = c.user_id
  where c.post_id = p_post_id
    and c.deleted_at is null
    and public.post_engagement_visible(p_post_id)
    -- Blocked users' comments stay hidden, matching comments_block_filter.
    and not public.is_blocked_user(auth.uid(), c.user_id)
  order by c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 20), 100));
$function$;

-- The real total (the list above is capped). Same gate, no identity at all.
CREATE OR REPLACE FUNCTION public.anon_post_comment_count(p_post_id uuid)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  select count(*)::integer
  from public.comments c
  where c.post_id = p_post_id
    and c.deleted_at is null
    and public.post_engagement_visible(p_post_id)
    and not public.is_blocked_user(auth.uid(), c.user_id);
$function$;

REVOKE ALL ON FUNCTION public.anon_post_comments(uuid, integer) FROM public;
REVOKE ALL ON FUNCTION public.anon_post_comment_count(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.anon_post_comments(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.anon_post_comment_count(uuid) TO authenticated;
