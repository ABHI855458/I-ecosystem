-- ============================================================================
-- react_ping_realmoji() / unreact_ping_realmoji() — the client's write path
-- for ping RealMoji reactions (20261003100000).
--
-- One reaction per person per target, and reacting again REPLACES it (same
-- as the feed). The uniqueness lives in two PARTIAL indexes, which
-- PostgREST's upsert can't target, so the replace is done here. Runs as
-- the caller (SECURITY INVOKER): the table's own RLS — can_react_ping_target
-- — is what decides whether this reaction is allowed at all.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.react_ping_realmoji(
  p_reply uuid,
  p_ping uuid,
  p_type text
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF (p_reply IS NULL) = (p_ping IS NULL) THEN
    RAISE EXCEPTION 'React to exactly one reply or ping.';
  END IF;

  IF p_reply IS NOT NULL THEN
    UPDATE public.ping_realmoji_reactions
       SET emoji_type = p_type::public.emoji_type_enum, created_at = now()
     WHERE ping_reply_id = p_reply AND user_id = v_me;
    IF NOT FOUND THEN
      INSERT INTO public.ping_realmoji_reactions (ping_reply_id, user_id, emoji_type)
      VALUES (p_reply, v_me, p_type::public.emoji_type_enum);
    END IF;
  ELSE
    UPDATE public.ping_realmoji_reactions
       SET emoji_type = p_type::public.emoji_type_enum, created_at = now()
     WHERE ping_id = p_ping AND user_id = v_me;
    IF NOT FOUND THEN
      INSERT INTO public.ping_realmoji_reactions (ping_id, user_id, emoji_type)
      VALUES (p_ping, v_me, p_type::public.emoji_type_enum);
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.unreact_ping_realmoji(p_reply uuid, p_ping uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY INVOKER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  DELETE FROM public.ping_realmoji_reactions
   WHERE user_id = public.current_user_id()
     AND ((p_reply IS NOT NULL AND ping_reply_id = p_reply)
       OR (p_ping IS NOT NULL AND ping_id = p_ping));
$function$;

REVOKE ALL ON FUNCTION public.react_ping_realmoji(uuid, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unreact_ping_realmoji(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.react_ping_realmoji(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unreact_ping_realmoji(uuid, uuid) TO authenticated;

COMMIT;
