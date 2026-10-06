-- ============================================================================
-- Reactions on group chat messages (explicit request, 2026-10-04: "give
-- reactions for messages to react on messages as such like in WhatsApp").
--
-- A plain emoji per person per message — not RealMoji: chat reactions are
-- tapped mid-conversation and must never open a selfie camera. One reaction
-- per person per message; tapping a different emoji replaces it, tapping the
-- same one clears it.
--
-- Visibility follows the message: only members of that group can see or
-- leave one, and only while the message is still alive (group chat is purged
-- after 48h). Reactions go with the message — ON DELETE CASCADE — so the
-- hourly purge cleans them up too.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.group_message_reactions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.group_messages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji      text NOT NULL CHECK (char_length(emoji) BETWEEN 1 AND 16),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS group_message_reactions_message_idx
  ON public.group_message_reactions (message_id);

ALTER TABLE public.group_message_reactions ENABLE ROW LEVEL SECURITY;

-- Member of the message's group, and the message must still exist.
CREATE OR REPLACE FUNCTION public.can_see_group_message(p_message uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.group_messages m
      JOIN public.group_members gm ON gm.group_id = m.group_id
     WHERE m.id = p_message
       AND m.deleted_at IS NULL
       AND gm.user_id = public.current_user_id()
  );
$function$;

REVOKE ALL ON FUNCTION public.can_see_group_message(uuid) FROM PUBLIC, anon;
-- The policies below call this as the CALLER (SECURITY INVOKER paths), so
-- authenticated must be able to execute it — unlike the leak helpers locked
-- down in 20261004000000, which no policy uses.
GRANT EXECUTE ON FUNCTION public.can_see_group_message(uuid) TO authenticated;

DROP POLICY IF EXISTS gmr_select_member ON public.group_message_reactions;
CREATE POLICY gmr_select_member ON public.group_message_reactions
  FOR SELECT USING (public.can_see_group_message(message_id));

DROP POLICY IF EXISTS gmr_insert_own ON public.group_message_reactions;
CREATE POLICY gmr_insert_own ON public.group_message_reactions
  FOR INSERT WITH CHECK (
    user_id = public.current_user_id()
    AND public.can_see_group_message(message_id)
  );

DROP POLICY IF EXISTS gmr_update_own ON public.group_message_reactions;
CREATE POLICY gmr_update_own ON public.group_message_reactions
  FOR UPDATE USING (user_id = public.current_user_id())
  WITH CHECK (user_id = public.current_user_id());

DROP POLICY IF EXISTS gmr_delete_own ON public.group_message_reactions;
CREATE POLICY gmr_delete_own ON public.group_message_reactions
  FOR DELETE USING (user_id = public.current_user_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.group_message_reactions TO authenticated;

-- One call for the whole toggle: set, replace, or clear (same emoji again).
-- SECURITY INVOKER — the policies above are the gate.
CREATE OR REPLACE FUNCTION public.react_group_message(p_message uuid, p_emoji text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid := public.current_user_id(); v_existing text;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_emoji IS NULL OR btrim(p_emoji) = '' THEN
    DELETE FROM public.group_message_reactions
     WHERE message_id = p_message AND user_id = v_me;
    RETURN NULL;
  END IF;

  SELECT emoji INTO v_existing
    FROM public.group_message_reactions
   WHERE message_id = p_message AND user_id = v_me;

  IF v_existing = p_emoji THEN
    DELETE FROM public.group_message_reactions
     WHERE message_id = p_message AND user_id = v_me;
    RETURN NULL;
  ELSIF v_existing IS NOT NULL THEN
    UPDATE public.group_message_reactions
       SET emoji = p_emoji, created_at = now()
     WHERE message_id = p_message AND user_id = v_me;
  ELSE
    INSERT INTO public.group_message_reactions (message_id, user_id, emoji)
    VALUES (p_message, v_me, p_emoji);
  END IF;
  RETURN p_emoji;
END;
$function$;

REVOKE ALL ON FUNCTION public.react_group_message(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.react_group_message(uuid, text) TO authenticated;

-- Every reaction on a page of messages, in one read.
CREATE OR REPLACE FUNCTION public.group_message_reactions_for(p_ids uuid[])
 RETURNS TABLE(message_id uuid, emoji text, n int, mine boolean, who text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT x.message_id,
         x.emoji,
         COUNT(*)::int,
         bool_or(x.user_id = (SELECT uid FROM me)),
         string_agg(COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Someone'), ', ')
    FROM public.group_message_reactions x
    LEFT JOIN public.users u ON u.id = x.user_id
   WHERE x.message_id = ANY (COALESCE(p_ids, '{}'))
     AND public.can_see_group_message(x.message_id)
   GROUP BY x.message_id, x.emoji
   ORDER BY COUNT(*) DESC;
$function$;

REVOKE ALL ON FUNCTION public.group_message_reactions_for(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_message_reactions_for(uuid[]) TO authenticated;

COMMIT;
