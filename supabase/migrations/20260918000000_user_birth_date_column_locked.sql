-- Date of birth, collected once at onboarding for Play Store content-rating
-- compliance (target audience spans 16-17 and 18+, which requires a neutral
-- age screen). Never displayed, never returned to another user.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS birth_date date;

COMMENT ON COLUMN public.users.birth_date IS
  'Self-reported DOB, onboarding-only, for Play content-rating compliance. Column-level REVOKEd from anon/authenticated; read via my_age_status(), written via set_my_birth_date().';

-- is_minor is a FUNCTION, not a stored/generated column, on purpose: the
-- answer depends on today's date, so any stored value is wrong the morning a
-- 17-year-old turns 18. (Postgres refuses CURRENT_DATE in a generated column
-- for exactly this reason.) Computed live, it is always correct.
--
-- Returns NULL when birth_date is unset — "unknown", deliberately distinct
-- from false ("known adult"), so an unanswered account is never mistaken for
-- a verified adult. This is the single place future minor-specific behaviour
-- should check.
CREATE OR REPLACE FUNCTION public.user_is_minor(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
  SELECT CASE WHEN u.birth_date IS NULL THEN NULL
              ELSE u.birth_date > (CURRENT_DATE - INTERVAL '18 years')
         END
    FROM public.users u WHERE u.id = p_user_id;
$$;

-- Table-level grants would override any column-level exclusion, so they are
-- dropped and re-issued per column. Done dynamically rather than as a fixed
-- list so a column added later is granted normally — only birth_date stays
-- locked, and it fails CLOSED (a wildcard select errors rather than quietly
-- omitting it).
DO $$
DECLARE cols text;
BEGIN
  REVOKE SELECT, INSERT, UPDATE ON public.users FROM authenticated, anon;

  SELECT string_agg(quote_ident(column_name), ', ')
    INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'users'
     AND column_name <> 'birth_date';
  EXECUTE format('GRANT SELECT (%s) ON public.users TO authenticated, anon', cols);

  SELECT string_agg(quote_ident(column_name), ', ')
    INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'users'
     AND column_name <> 'birth_date'
     AND is_generated = 'NEVER';
  EXECUTE format('GRANT INSERT (%s), UPDATE (%s) ON public.users TO authenticated, anon', cols, cols);
END $$;

-- The only write path. SECURITY DEFINER so the caller never needs the column
-- privilege; scoped to the caller's own row by construction.
CREATE OR REPLACE FUNCTION public.set_my_birth_date(p_birth_date date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_me uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_birth_date IS NULL
     OR p_birth_date > CURRENT_DATE
     OR p_birth_date < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'Enter a valid date of birth.';
  END IF;
  UPDATE public.users SET birth_date = p_birth_date WHERE id = v_me;
END; $$;

-- The only read path, and it only ever returns the CALLER's own values.
CREATE OR REPLACE FUNCTION public.my_age_status()
RETURNS TABLE(birth_date date, is_minor boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
  SELECT u.birth_date, public.user_is_minor(u.id)
    FROM public.users u
   WHERE u.id = public.current_user_id();
$$;

GRANT EXECUTE ON FUNCTION public.set_my_birth_date(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_age_status() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.user_is_minor(uuid) FROM authenticated, anon;
