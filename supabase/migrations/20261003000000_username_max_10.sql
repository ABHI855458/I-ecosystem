-- ============================================================================
-- New usernames max 10 chars (explicit request, 2026-10-02: "keep the words
-- limit so that the username correctly fits in ping page and camera
-- section"). Client: AppStrings.usernameMaxLength = 10.
--
-- Deliberately a trigger, not a tighter users_username_format CHECK: ~10
-- existing users already have longer names, and a CHECK (even NOT VALID)
-- is re-evaluated on every later UPDATE of those rows — it would break
-- unrelated profile writes for them. This only fires when a username is
-- SET or CHANGED, so existing names keep working untouched.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_username_max_10()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.username IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.username IS DISTINCT FROM OLD.username)
     AND char_length(NEW.username) > 10 THEN
    RAISE EXCEPTION 'Username must be 10 characters or fewer.'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_username_max_10 ON public.users;
CREATE TRIGGER trg_username_max_10
  BEFORE INSERT OR UPDATE OF username ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.enforce_username_max_10();

REVOKE ALL ON FUNCTION public.enforce_username_max_10() FROM PUBLIC, anon, authenticated;

COMMIT;
