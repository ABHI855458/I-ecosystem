-- Age-gate bypass: set_my_birth_date() correctly enforces 13+ server-side,
-- but nothing ever required it to have been CALLED before onboarding could
-- complete. CurrentUserService.markOnboardingComplete() is a bare
-- `UPDATE users SET onboarding_completed = true` with no birth_date check
-- anywhere in RLS or any other function (verified: zero policies, zero
-- other functions reference birth_date). A client that skips the app's own
-- onboarding UI — a modified build, or a direct authenticated API call —
-- could flip onboarding_completed straight to true with birth_date
-- permanently NULL, never age-checked at all.
--
-- Fixed as a trigger rather than an RPC-only gate: a trigger closes this
-- regardless of which path tries to set the flag (the existing plain
-- `.update()` call, a future RPC, anything) — the same "structural, not
-- convention" standard the rest of this schema already holds to (e.g.
-- circle_member_is_eligible via WITH CHECK, lock_notification_fields via
-- trigger). Onboarding's only real caller (onboarding_screen.dart's
-- _done()) already calls set_my_birth_date() BEFORE this update, so the
-- normal flow is unaffected — verified live below.
-- Guards the TRANSITION into onboarding_completed=true, not the persisted
-- state — every one of the 9 real accounts in this database predates the
-- birth_date column entirely (onboarding_completed already true,
-- birth_date NULL, from before this feature existed). An unconditional
-- `NEW.onboarding_completed AND NEW.birth_date IS NULL` check — caught
-- live, before shipping, by this same migration's own verification step
-- below — would have raised on EVERY future update to EVERY existing
-- user's row for ANY reason (a score change, a streak tick, a profile
-- edit — anything), since an UPDATE that doesn't mention either column
-- carries both columns' OLD values through as NEW unchanged. Gating on
-- "was it not-true a moment ago" scopes this to exactly the bypass being
-- closed (a fresh account completing onboarding) and leaves every
-- legacy/already-onboarded row's future updates untouched.
CREATE OR REPLACE FUNCTION public.enforce_onboarding_requires_birth_date()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.onboarding_completed
     AND NOT COALESCE(OLD.onboarding_completed, false)
     AND NEW.birth_date IS NULL THEN
    RAISE EXCEPTION 'Cannot complete onboarding without a date of birth.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_require_birth_date_for_onboarding
BEFORE UPDATE ON public.users
FOR EACH ROW EXECUTE FUNCTION public.enforce_onboarding_requires_birth_date();
