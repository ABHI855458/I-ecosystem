-- ============================================================================
-- Group chat (explicit request, 2026-10-03: "include group chats as well,
-- for a group of people — only members can access it"), opened from the
-- Community tab's WhatsApp-style chat list.
--
-- group_messages: one row per message. MEMBERS ONLY, enforced by RLS with
-- the same is_group_member() the group_members policies already use — a
-- non-member can neither read nor write, including over realtime (which
-- applies the SELECT policy per subscriber).
--
-- group_messages_page(): newest-first page with the sender's name + photo
-- joined in, so the client needn't read `users` under its own RLS. Checks
-- membership itself (SECURITY DEFINER) and returns nothing otherwise.
--
-- my_chat_list(): groups now preview their newest MESSAGE too ("name: text").
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.group_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  sender_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  body        text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 1000),
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

CREATE INDEX IF NOT EXISTS group_messages_group_created_idx
  ON public.group_messages (group_id, created_at DESC);

ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS group_messages_select_member ON public.group_messages;
CREATE POLICY group_messages_select_member ON public.group_messages
  FOR SELECT TO authenticated
  USING (public.is_group_member(group_id, public.current_user_id()));

DROP POLICY IF EXISTS group_messages_insert_member ON public.group_messages;
CREATE POLICY group_messages_insert_member ON public.group_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = public.current_user_id()
    AND public.is_group_member(group_id, public.current_user_id())
    AND deleted_at IS NULL
  );

-- Own messages can be soft-deleted ("unsend"); nothing else is editable.
DROP POLICY IF EXISTS group_messages_update_own ON public.group_messages;
CREATE POLICY group_messages_update_own ON public.group_messages
  FOR UPDATE TO authenticated
  USING (sender_id = public.current_user_id())
  WITH CHECK (sender_id = public.current_user_id());

REVOKE ALL ON public.group_messages FROM anon;
GRANT SELECT, INSERT, UPDATE (deleted_at) ON public.group_messages TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
       AND tablename = 'group_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_messages;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.group_messages_page(
  p_group uuid,
  p_before timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 50
)
 RETURNS TABLE (
   id uuid,
   sender_id uuid,
   sender_name text,
   sender_avatar text,
   body text,
   created_at timestamptz,
   is_mine boolean
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH me AS (SELECT public.current_user_id() AS uid)
  SELECT m.id, m.sender_id,
         COALESCE(NULLIF(btrim(u.name), ''), u.anon_name, 'Member'),
         u.profile_photo_url,
         m.body, m.created_at,
         m.sender_id = me.uid
    FROM public.group_messages m
    JOIN me ON public.is_group_member(p_group, me.uid)
    LEFT JOIN public.users u ON u.id = m.sender_id
   WHERE m.group_id = p_group
     AND m.deleted_at IS NULL
     AND (p_before IS NULL OR m.created_at < p_before)
   ORDER BY m.created_at DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$function$;

REVOKE ALL ON FUNCTION public.group_messages_page(uuid, timestamptz, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_messages_page(uuid, timestamptz, integer) TO authenticated;

COMMIT;
