-- Phase 3 — Branch detection + app-wide config.
--
-- profiles.branch/profiles.year already exist (schema.sql/live) but are
-- 100% NULL — nothing has ever written them. handle_new_user() (the
-- on_auth_user_created trigger on auth.users) reads branch/year from
-- raw_user_meta_data, which the client never populates at signup — that
-- path is dead, not this one. This migration derives branch/year from the
-- RVCE email pattern instead, server-side, so it works retroactively and
-- for every future signup regardless of what the client sends.
--
-- Confirmed against the only two real @rvce.edu.in accounts in the live
-- DB: 'abhisheksdpatel.cs25@rvce.edu.in' -> ('cs','25'); a plain
-- 'student@rvce.edu.in' (no dot-segment) correctly derives to NULL.
--
-- app_config is a small key/value table for two settings that both ship
-- SAFE-by-default and are meant to be flipped by hand in the SQL editor,
-- never in application code:
--   - require_college_email_domain (default true) — gates new signups to
--     @rvce.edu.in. The existing gmail test accounts are unaffected; this
--     only applies to auth.users INSERT going forward.
--   - visitor_branch_min_students (default 100) — the branch-visitor
--     notification threshold (Phase 4). With today's data (largest branch
--     = 1 student) it fires for nobody, which is correct.

CREATE TABLE IF NOT EXISTS public.app_config (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_config_read ON public.app_config;
CREATE POLICY app_config_read ON public.app_config
  FOR SELECT TO authenticated USING (true);
-- No INSERT/UPDATE/DELETE policy — only service_role (which bypasses RLS,
-- i.e. the SQL editor / an Edge Function with the service key) can write.

CREATE OR REPLACE FUNCTION public.touch_app_config_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_app_config ON public.app_config;
CREATE TRIGGER trg_touch_app_config
  BEFORE UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.touch_app_config_updated_at();

INSERT INTO public.app_config (key, value) VALUES
  ('visitor_branch_min_students', '100'::jsonb),
  ('require_college_email_domain', 'true'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- derive_branch — the RVCE email convention is <name(.name)*>.<branch><yy>
-- @rvce.edu.in. The greedy `.+\.` anchors to the LAST dot, so
-- 'first.last.cs25@rvce.edu.in' still yields 'cs'/'25'. No branch
-- whitelist deliberately — RVCE has more branches than any hardcoded list
-- would include (is/ee/ch/ds/et/im/...), and a typo'd or unrecognized
-- branch is naturally filtered out by the 100+ threshold rather than
-- silently dropping a real student.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.derive_branch(p_email text)
RETURNS TABLE(branch text, year int)
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT
    (regexp_match(lower(trim(p_email)), '^.+\.([a-z]{2,4})(\d{2})@rvce\.edu\.in$'))[1],
    nullif((regexp_match(lower(trim(p_email)), '^.+\.([a-z]{2,4})(\d{2})@rvce\.edu\.in$'))[2], '')::int;
$function$;

REVOKE ALL ON FUNCTION public.derive_branch(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.derive_branch(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- sync_profile_branch — keeps profiles.branch/year in step with
-- users.email. Bridges users.id -> users.auth_id -> profiles.id (the same
-- keyspace bridge shares_community uses), since branch lives on `profiles`
-- but email lives on `users`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_profile_branch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_branch text;
  v_year int;
BEGIN
  SELECT branch, year INTO v_branch, v_year FROM public.derive_branch(NEW.email);
  IF NEW.auth_id IS NOT NULL THEN
    UPDATE public.profiles SET branch = v_branch, year = v_year WHERE id = NEW.auth_id;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_profile_branch() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_profile_branch ON public.users;
CREATE TRIGGER trg_sync_profile_branch
  AFTER INSERT OR UPDATE OF email ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_branch();

-- One-time backfill over existing users/profiles. Only touches profiles
-- with a matching users row (the join) — the 5 profiles orphaned from any
-- users row are left alone, same as they already are.
UPDATE public.profiles p
SET branch = d.branch, year = d.year
FROM public.users u, LATERAL public.derive_branch(u.email) d
WHERE p.id = u.auth_id;

-- ---------------------------------------------------------------------------
-- branch_student_counts — per-branch headcount, the Phase 4 visitor
-- notification's 100+ gate. Excludes soft-deleted users.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.branch_student_counts()
RETURNS TABLE(branch text, student_count bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.branch, count(*)
  FROM public.profiles p
  JOIN public.users u ON u.auth_id = p.id
  WHERE p.branch IS NOT NULL AND u.deleted_at IS NULL
  GROUP BY p.branch;
$function$;

REVOKE ALL ON FUNCTION public.branch_student_counts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.branch_student_counts() TO authenticated;

-- ---------------------------------------------------------------------------
-- enforce_college_email_domain — safe-by-default signup gate. Reads
-- app_config so it can be toggled off for local/dev testing without a code
-- change; defaults to enforcing (true) if the config row is ever missing.
-- Applies only to NEW signups — the existing gmail test accounts already
-- in auth.users are untouched.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_college_email_domain()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_required boolean := true;
BEGIN
  SELECT COALESCE((value #>> '{}')::boolean, true) INTO v_required
  FROM public.app_config WHERE key = 'require_college_email_domain';

  IF v_required AND lower(NEW.email) NOT LIKE '%@rvce.edu.in' THEN
    RAISE EXCEPTION 'Signups are currently restricted to @rvce.edu.in email addresses';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enforce_college_email_domain() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_enforce_college_email_domain ON auth.users;
CREATE TRIGGER trg_enforce_college_email_domain
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.enforce_college_email_domain();
