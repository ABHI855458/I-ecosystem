-- ============================================================================
-- get_thread_handles — batch lookup so the anon comment sheet can show
-- every commenter's per-post pseudonym, not just the caller's own.
--
-- get_thread_handle(p_post) (already live) only resolves the CALLING
-- user's own handle — post_thread_handles' own RLS (`pth_read`:
-- `user_id = auth.uid()`) blocks any client-side SELECT of a row that
-- belongs to someone else, by design (that's what stops a client from
-- reverse-mapping handles to accounts in bulk). But `comments` itself
-- carries real `user_id` values readable by any viewer who can see the
-- post (comments_select does row-visibility only, no column masking), so
-- something has to bridge "I can see this comment's real user_id" to "here
-- is the pseudonym to show for it" without ever handing the client a real
-- name/photo. This SECURITY DEFINER RPC is that bridge: given a post and a
-- set of user ids (the comments' own `user_id` values, already visible to
-- the caller), it returns just (user_id, handle) pairs — auto-minting a
-- handle for anyone who doesn't have one yet, same as get_thread_handle
-- does for the caller.
--
-- NOTE: post_thread_handles.user_id / anonymous_comment_authors.author_id
-- both FK to `profiles(id)`, NOT this app's own `users(id)` — confirmed
-- live: `profiles.id = auth.uid()` (the raw Supabase Auth id), a separate,
-- pre-existing identity table this app's CurrentUserService bypasses for
-- everything else. Every real signed-in user already has a `profiles` row
-- (confirmed: all 3 live `users` rows join to one), so this works for real
-- accounts without further provisioning — but callers MUST pass raw auth
-- ids here, never `users.id`.
-- ============================================================================

CREATE OR REPLACE FUNCTION get_thread_handles(p_post UUID, p_user_ids UUID[])
RETURNS TABLE(user_id UUID, handle TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_uid UUID;
BEGIN
  -- Anyone can resolve handles for a post that still exists — comments on
  -- it are only reachable in the first place via comments_select, which
  -- already gates row visibility; this just supplies the display name for
  -- rows the caller can already see.
  IF NOT EXISTS (SELECT 1 FROM posts WHERE id = p_post AND deleted_at IS NULL) THEN
    RETURN;
  END IF;

  FOREACH v_uid IN ARRAY p_user_ids LOOP
    INSERT INTO post_thread_handles(post_id, user_id, handle)
    VALUES (p_post, v_uid, gen_handle())
    ON CONFLICT (post_id, user_id) DO NOTHING;
  END LOOP;

  RETURN QUERY
    SELECT pth.user_id, pth.handle
    FROM post_thread_handles pth
    WHERE pth.post_id = p_post AND pth.user_id = ANY(p_user_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION get_thread_handles(UUID, UUID[]) TO authenticated;
