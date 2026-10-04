-- Stale-login re-verification: returns TRUE when an account has not signed
-- in within the window and should be made to re-verify by email.
--
-- SHIPPED INACTIVE ON PURPOSE. Nothing calls this yet — the client login path
-- (auth_screen.dart) is deliberately unchanged. It exists now so the review
-- account exemption below is already in place before the feature is ever
-- switched on, rather than being remembered later.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_login_at timestamptz;

CREATE OR REPLACE FUNCTION public.touch_login_needs_reverify(p_window_hours int DEFAULT 72)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_temp'
AS $$
DECLARE v_me uuid; v_email text; v_last timestamptz; v_needs boolean;
BEGIN
  v_me := public.current_user_id();
  IF v_me IS NULL THEN RETURN false; END IF;

  -- Play Store review account never re-verifies. Exact match, not a pattern
  -- and not a domain: a reviewer returning after 3+ days must not hit an OTP
  -- gate they have no way to receive. Stamped and returned before any window
  -- maths so no future change to the window can catch it.
  SELECT lower(au.email) INTO v_email FROM auth.users au WHERE au.id = auth.uid();
  IF v_email = 'playstore-review@useiapp.online' THEN
    UPDATE public.users SET last_login_at = now() WHERE id = v_me;
    RETURN false;
  END IF;

  SELECT last_login_at INTO v_last FROM public.users WHERE id = v_me;
  -- First ever login is NOT stale: signup already verified by OTP.
  v_needs := v_last IS NOT NULL
             AND v_last < now() - make_interval(hours => p_window_hours);
  UPDATE public.users SET last_login_at = now() WHERE id = v_me;
  RETURN v_needs;
END; $$;

GRANT EXECUTE ON FUNCTION public.touch_login_needs_reverify(int) TO authenticated;
