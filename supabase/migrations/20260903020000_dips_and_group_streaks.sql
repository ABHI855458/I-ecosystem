-- ============================================================================
-- Dip feature: per-group ephemeral photo posts + per-group daily streak,
-- plus a non-member-safe public group profile RPC and two group_posts
-- metadata columns (taken_at, note).
--
-- CONFIRMED against the live database on 2026-09-02 via the Supabase MCP
-- (schema.sql is stale — do not trust it): no `dips`, `group_dips`, or
-- `streaks` table exists anywhere; `group_posts` has no `deleted_at` column
-- and no UPDATE policy (GroupService.deletePost's soft-delete was silently
-- broken — fixed in the same app change that ships this migration, not
-- here); `is_group_member(uuid,uuid)` and `is_group_member(uuid,uuid,text)`
-- both already exist live and are reused below rather than duplicated.
--
-- Every statement is idempotent, safe to re-run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. dips — one row per photo, member-only, expires 24h after posting.
-- Expiry follows the anon-feed pattern (posts_visibility_created_idx /
-- FeedService.anonCutoff): rows are never deleted, reads filter on
-- expires_at. Unlike Moments (posts.post_type='moment', whose "24h" is a
-- purely cosmetic client-side label with no real query filter — confirmed
-- via feed_service.dart's fetchMyMoments having no age filter at all),
-- expires_at here is a real stored column so the countdown is server truth.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.dips (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id)  ON DELETE CASCADE,
  photo_url  TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS dips_group_created_idx ON public.dips (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS dips_group_user_created_idx ON public.dips (group_id, user_id, created_at DESC);

ALTER TABLE public.dips ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'dips' AND policyname = 'dips_select') THEN
    CREATE POLICY "dips_select" ON public.dips FOR SELECT USING (
      is_group_member(group_id, (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()))
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'dips' AND policyname = 'dips_insert') THEN
    CREATE POLICY "dips_insert" ON public.dips FOR INSERT WITH CHECK (
      user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
      AND is_group_member(group_id, (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()))
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'dips' AND policyname = 'dips_delete') THEN
    CREATE POLICY "dips_delete" ON public.dips FOR DELETE USING (
      user_id = (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid())
      OR is_group_member(group_id, (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()), 'admin')
    );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. group_streaks — separate from the existing "Ping streak", which is
-- confirmed to be entirely client-side (shared_preferences in
-- streak_service.dart, device-local DateTime.now(), no DB table at all —
-- users.streak/users.posted_today exist but nothing writes them). This one
-- is real, server-maintained, and keyed per (group, user). Day boundary is
-- Asia/Kolkata (campus app, @rvce.edu.in domain-gated).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.group_streaks (
  group_id       UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES public.users(id)  ON DELETE CASCADE,
  current_streak INT  NOT NULL DEFAULT 0,
  longest_streak INT  NOT NULL DEFAULT 0,
  last_dip_on    DATE,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

ALTER TABLE public.group_streaks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'group_streaks' AND policyname = 'group_streaks_select') THEN
    CREATE POLICY "group_streaks_select" ON public.group_streaks FOR SELECT USING (
      is_group_member(group_id, (SELECT u.id FROM public.users u WHERE u.auth_id = auth.uid()))
    );
  END IF;
END $$;
-- No INSERT/UPDATE policy: only the SECURITY DEFINER trigger below writes.

CREATE OR REPLACE FUNCTION public.bump_group_streak()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  d    DATE := (new.created_at AT TIME ZONE 'Asia/Kolkata')::date;
  prev DATE;
BEGIN
  SELECT last_dip_on INTO prev FROM group_streaks
    WHERE group_id = new.group_id AND user_id = new.user_id;

  IF prev = d THEN
    RETURN new;                                   -- already dipped today, no change
  END IF;

  INSERT INTO group_streaks (group_id, user_id, current_streak, longest_streak, last_dip_on, updated_at)
  VALUES (new.group_id, new.user_id, 1, 1, d, now())
  ON CONFLICT (group_id, user_id) DO UPDATE SET
    current_streak = CASE WHEN group_streaks.last_dip_on = d - 1
                          THEN group_streaks.current_streak + 1 ELSE 1 END,
    longest_streak = GREATEST(group_streaks.longest_streak,
                       CASE WHEN group_streaks.last_dip_on = d - 1
                            THEN group_streaks.current_streak + 1 ELSE 1 END),
    last_dip_on    = d,
    updated_at     = now();
  RETURN new;
END $$;

DROP TRIGGER IF EXISTS dips_bump_streak ON public.dips;
CREATE TRIGGER dips_bump_streak AFTER INSERT ON public.dips
  FOR EACH ROW EXECUTE FUNCTION public.bump_group_streak();

-- A stored current_streak goes stale once someone stops dipping (the
-- trigger only fires on new dips) — every read decays it to 0 once more
-- than a day has passed since last_dip_on, so member and non-member views
-- (which both call this) agree without a cron job.
CREATE OR REPLACE FUNCTION public.effective_group_streak(p_current INT, p_last DATE)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_last IS NULL THEN 0
    WHEN p_last >= ((now() AT TIME ZONE 'Asia/Kolkata')::date - 1) THEN COALESCE(p_current, 0)
    ELSE 0
  END;
$$;

-- ---------------------------------------------------------------------------
-- 3. group_public_profile — the only thing a non-member of a group may
-- read: identity + roster + each member's decayed streak. No dips, no
-- posts, by construction (dips/group_posts RLS stays member-only; this
-- function never selects from either table). SECURITY DEFINER so it can
-- read groups/group_members/users on the caller's behalf without widening
-- those tables' own RLS.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.group_public_profile(p_group_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id',           g.id,
    'name',         g.name,
    'icon_url',     g.icon_url,
    'member_count', (SELECT count(*) FROM group_members m WHERE m.group_id = g.id),
    'members', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id',           u.id,
               'name',              u.name,
               'profile_photo_url', u.profile_photo_url,
               'streak',            effective_group_streak(gs.current_streak, gs.last_dip_on)
             ) ORDER BY u.name)
      FROM group_members m
      JOIN users u ON u.id = m.user_id
      LEFT JOIN group_streaks gs ON gs.group_id = m.group_id AND gs.user_id = m.user_id
      WHERE m.group_id = g.id
    ), '[]'::jsonb)
  )
  FROM groups g
  WHERE g.id = p_group_id;
$$;

REVOKE ALL ON FUNCTION public.group_public_profile(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.group_public_profile(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. group_posts metadata — optional "memory" context on a regular group
-- post (not a Dip): when it was actually taken, and a short note. No
-- deleted_at is added here — live group_posts already has a working
-- own-or-admin DELETE policy (delete_group_posts); GroupService.deletePost
-- was calling an UPDATE against a column that never existed, fixed
-- app-side by switching it to a real DELETE.
-- ---------------------------------------------------------------------------

ALTER TABLE public.group_posts
  ADD COLUMN IF NOT EXISTS taken_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS note     TEXT;
