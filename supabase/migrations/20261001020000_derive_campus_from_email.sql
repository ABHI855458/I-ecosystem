-- ============================================================================
-- "· RVCE" on every profile was a hardcoded string (see profile_v2_data.dart
-- / profile_lookup_service.dart's own comments: "no campus column exists
-- anywhere in this schema... DO NOT wire these to a real query without a
-- real column backing them first") — shown even for the outsider accounts
-- 20260929070000_allow_any_email_domain.sql explicitly allowed in. This adds
-- that real column, derived from the account's own email domain, so the
-- label only shows for an actual institutional account and is absent (null)
-- for everyone else.
--
-- `users.email` itself stays locked down (SELECT revoked from authenticated/
-- anon — confirmed live): only the derived label is exposed, same posture
-- `profiles.branch` already has (20260924030000's own doc: "the same
-- academic-branch fact already shown in public profile headers... not a new
-- exposure"). A new column defaults to table-wide SELECT grants, so `campus`
-- is readable like `name`/`username` with no extra GRANT needed.
--
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.derive_campus(p_email text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT CASE
    WHEN lower(trim(p_email)) LIKE '%@rvce.edu.in' THEN 'RVCE'
    WHEN lower(trim(p_email)) LIKE '%@rvu.edu.in' THEN 'RVU'
    ELSE NULL
  END;
$$;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS campus text;

UPDATE public.users
   SET campus = public.derive_campus(email)
 WHERE campus IS DISTINCT FROM public.derive_campus(email);

CREATE OR REPLACE FUNCTION public.sync_user_campus()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  NEW.campus := public.derive_campus(NEW.email);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_sync_user_campus ON public.users;
CREATE TRIGGER trg_sync_user_campus
  BEFORE INSERT OR UPDATE OF email ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_user_campus();

COMMIT;

-- New columns here don't inherit table-wide SELECT (grants on this table are
-- column-listed, not blanket — confirmed live: the new `campus` column had
-- no authenticated/anon SELECT until granted explicitly).
GRANT SELECT (campus) ON public.users TO authenticated, anon;
