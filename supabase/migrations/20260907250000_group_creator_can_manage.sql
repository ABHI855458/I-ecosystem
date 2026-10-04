-- ============================================================================
-- The group's CREATOR can set its photo, banner and name — not only an
-- admin MEMBER.
--
-- Reported as "see if you're able to set dp for group profiles". The UI, the
-- storage upload and GroupService.updateGroupInfo were all correct and
-- wired; the UPDATE was refused by RLS and, as always on this project, that
-- surfaces as zero rows changed rather than an error — the picker appeared
-- to work and the photo simply never changed.
--
-- Why it was refused: groups_update_admin requires a group_members row with
-- role='admin' for the caller, and 'bakchodi crew' (and 'Curl Test B
-- Minimal') have NO group_members rows at all — not even their creator's.
-- So no one on earth could edit those groups.
--
-- Two changes:
--
--   1. UPDATE and DELETE now also admit `groups.created_by`. This is not a
--      workaround for the missing rows — it is the rule those policies
--      should always have had, and it is exactly what the group_members
--      INSERT policy (admin_add_members) already does. If you made the
--      group, losing your membership row must not lock you out of your own
--      group permanently.
--
--   2. Backfill the missing creator-admin rows, so those groups behave like
--      every other group (member counts, rosters, the admin-only affordances
--      that key off membership rather than created_by).
--
-- The UPDATE policy gets an explicit WITH CHECK identical to its USING, so a
-- row cannot be edited into a state its editor could no longer reach.
--
-- Applied via `supabase db query --linked -f` (drifted ledger; db push unused).
-- ============================================================================

DROP POLICY IF EXISTS "groups_update_admin" ON public.groups;
CREATE POLICY "groups_update_admin" ON public.groups
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.group_members gm
      JOIN public.users u ON u.id = gm.user_id
     WHERE gm.group_id = groups.id
       AND gm.role = 'admin'
       AND u.auth_id = auth.uid()
  )
  OR groups.created_by IN (
    SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.group_members gm
      JOIN public.users u ON u.id = gm.user_id
     WHERE gm.group_id = groups.id
       AND gm.role = 'admin'
       AND u.auth_id = auth.uid()
  )
  OR groups.created_by IN (
    SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "groups_delete_admin" ON public.groups;
CREATE POLICY "groups_delete_admin" ON public.groups
FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM public.group_members gm
      JOIN public.users u ON u.id = gm.user_id
     WHERE gm.group_id = groups.id
       AND gm.role = 'admin'
       AND u.auth_id = auth.uid()
  )
  OR groups.created_by IN (
    SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()
  )
);

-- ── Backfill: every group's creator is an admin member of it ────────────────
-- ON CONFLICT covers the normal case where the row already exists.
INSERT INTO public.group_members (group_id, user_id, role)
SELECT gr.id, gr.created_by, 'admin'
  FROM public.groups gr
 WHERE gr.created_by IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = gr.id AND gm.user_id = gr.created_by
   )
ON CONFLICT DO NOTHING;
