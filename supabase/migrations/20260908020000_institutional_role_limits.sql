-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  Institutional role limits — enforce the spec's exclusions in RLS    ║
-- ╚══════════════════════════════════════════════════════════════════════╝
--
-- The Principal/Dean spec says they do NOT get ping-prompt management, the
-- full report queue, or the user database. The dashboard hides those pages,
-- but hiding a page is not enforcement — the account holds a real login and
-- the anon key, so anything RLS permits is reachable outside the UI.
--
-- Measured as the provisioned Dean before this ran:
--   ping_prompts  10 rows readable AND writable
--   reports        2 rows readable
--   moderators     3 rows readable (every moderator, not just self)
--
-- This narrows those three to admin. Nothing the Dean's job needs is
-- touched: viewing every feed, composing, priority announcements, removing
-- posts and creating communities all run off is_admin_or_global_mod() or the
-- dashboard_* RPCs, none of which change here.

-- ── 1. Ping-prompt management → admin only ─────────────────────────────
-- READS are deliberately left open: `pp_read` (active) is how the APP loads
-- the prompts into its ping sheet. Only authoring changes.

DROP POLICY IF EXISTS "ping_prompts_insert_moderator" ON public.ping_prompts;
DROP POLICY IF EXISTS "ping_prompts_update_moderator" ON public.ping_prompts;
DROP POLICY IF EXISTS "ping_prompts_delete_moderator" ON public.ping_prompts;

CREATE POLICY "ping_prompts_insert_admin" ON public.ping_prompts
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY "ping_prompts_update_admin" ON public.ping_prompts
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "ping_prompts_delete_admin" ON public.ping_prompts
  FOR DELETE USING (public.is_admin());

DROP POLICY IF EXISTS "ping_sheet_prompts_insert_moderator" ON public.ping_sheet_prompts;
DROP POLICY IF EXISTS "ping_sheet_prompts_update_moderator" ON public.ping_sheet_prompts;
DROP POLICY IF EXISTS "ping_sheet_prompts_delete_moderator" ON public.ping_sheet_prompts;

CREATE POLICY "ping_sheet_prompts_insert_admin" ON public.ping_sheet_prompts
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY "ping_sheet_prompts_update_admin" ON public.ping_sheet_prompts
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "ping_sheet_prompts_delete_admin" ON public.ping_sheet_prompts
  FOR DELETE USING (public.is_admin());

-- ── 2. Report queue → admin only ───────────────────────────────────────
-- rep_select_own is UNTOUCHED: that is how a student sees the reports they
-- filed, in the app's own settings screen. Only the moderator-wide view
-- narrows, so the Dean cannot read the campus report queue.

DROP POLICY IF EXISTS "rep_select_moderator" ON public.reports;
CREATE POLICY "rep_select_admin" ON public.reports
  FOR SELECT USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.posts p
       WHERE p.id = reports.post_id
         AND p.community_id IS NOT NULL
         AND public.is_community_moderator_for(p.community_id)
    )
  );

-- ── 3. Moderator roster → admin, or your own row ───────────────────────
-- A global moderator could enumerate every moderator account. Students are
-- unaffected — they were never admitted by this policy, so the app's
-- `moderators(email)` embed on announcements already resolved to null for
-- them and still does.

DROP POLICY IF EXISTS "moderators_select" ON public.moderators;
CREATE POLICY "moderators_select" ON public.moderators
  FOR SELECT USING (public.is_admin() OR email = auth.email());
