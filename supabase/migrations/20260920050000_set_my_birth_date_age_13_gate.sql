-- Real age-gate enforcement: a birth_date implying under 13 is now
-- rejected server-side, not just guarded client-side in
-- onboarding_screen.dart's _validateAge. The client check alone is a UX
-- nicety only — this RPC is callable directly (it's how the DOB write
-- happens at all, since birth_date is column-level REVOKEd from
-- authenticated), so anyone bypassing the app's own screen and calling it
-- straight would have sailed past the client's 13-year check entirely.
-- Previously the only bound here was a 120-year sanity ceiling — nothing
-- stopped a 5-year-old's real birth date, or a typo'd date, from being
-- accepted.
CREATE OR REPLACE FUNCTION public.set_my_birth_date(p_birth_date date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_me uuid;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF p_birth_date IS NULL
     OR p_birth_date > CURRENT_DATE
     OR p_birth_date < CURRENT_DATE - INTERVAL '120 years' THEN
    RAISE EXCEPTION 'Enter a valid date of birth.';
  END IF;
  -- THE FIX.
  IF p_birth_date > CURRENT_DATE - INTERVAL '13 years' THEN
    RAISE EXCEPTION 'You must be at least 13 years old to use this app.';
  END IF;
  UPDATE public.users SET birth_date = p_birth_date WHERE id = v_me;
END; $function$;
