-- ============================================================================
-- Moment replies can be posted anonymously.
--
-- "while replying to a moment give them the option to reply as anon or real
-- name" — the same post-as choice the composer already offers for a Moment
-- itself (composer_screen's momentAsAnon), now on the contribution.
--
-- Anonymity here is enforced in get_moment_replies, NOT in the client: the
-- function stops returning the name, avatar and user_id for an anonymous
-- reply, so a client that renders whatever it is handed cannot leak the
-- contributor even if it wants to. The row still stores user_id, because the
-- one-contribution-per-person unique index and the "have I contributed yet"
-- unlock both need it — it just never leaves the database attached to the
-- photo.
--
-- NOTE: this project's live migration ledger is drifted; this file is applied
-- with `supabase db query --linked -f`, not `db push`. Same convention as
-- 20260910000000_moment_replies.sql.
-- ============================================================================

ALTER TABLE public.moment_replies
  ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.moment_replies.is_anonymous IS
  'Posted as the contributor''s anon persona. get_moment_replies masks name, '
  'avatar and user_id when true — never rely on the client to hide them.';

-- ── get_moment_replies ──────────────────────────────────────────────────────
-- Same unlock as before (nothing until you have contributed; the Moment's
-- author is exempt), plus the masking above.
--
-- is_me stays truthful even for an anonymous row: it only ever tells YOU that
-- a row is yours, which you already know, and the client needs it to render
-- your own contribution as yours.

DROP FUNCTION IF EXISTS public.get_moment_replies(uuid);

CREATE FUNCTION public.get_moment_replies(p_post_id uuid)
 RETURNS TABLE(
   reply_id     uuid,
   user_id      uuid,
   name         text,
   avatar_url   text,
   photo_url    text,
   created_at   timestamptz,
   is_me        boolean,
   is_anonymous boolean
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_me     UUID;
  v_author UUID;
BEGIN
  SELECT u.id INTO v_me FROM public.users u WHERE u.auth_id = auth.uid();
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  SELECT p.user_id INTO v_author
    FROM public.posts p
   WHERE p.id = p_post_id
     AND p.post_type = 'moment'
     AND p.deleted_at IS NULL;
  IF v_author IS NULL THEN
    RETURN;
  END IF;

  -- Locked until you contribute. The author is exempt.
  IF v_me <> v_author AND NOT EXISTS (
    SELECT 1 FROM public.moment_replies r
     WHERE r.moment_post_id = p_post_id AND r.user_id = v_me
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT r.id,
         -- Masked for someone else's anonymous reply. Your own comes back
         -- with your id: you already know it is you.
         CASE WHEN r.is_anonymous AND r.user_id <> v_me
              THEN NULL::uuid ELSE r.user_id END,
         CASE WHEN r.is_anonymous
              THEN COALESCE(NULLIF(btrim(u.anon_name), ''), 'anonymous')
              ELSE u.name END,
         CASE WHEN r.is_anonymous THEN NULL::text
              ELSE u.profile_photo_url END,
         r.photo_url,
         r.created_at,
         (r.user_id = v_me),
         r.is_anonymous
    FROM public.moment_replies r
    JOIN public.users u ON u.id = r.user_id
   WHERE r.moment_post_id = p_post_id
   ORDER BY r.created_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_moment_replies(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_moment_replies(uuid) TO authenticated;
