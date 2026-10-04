-- Raises the hard per-prompt cap on active LINKED ping-prompts from 6 to
-- 10 — explicit request, to fit the Wake-pilot content's fixed 10-tag
-- pattern (Out-of-frame / Honest / Zoom-in / Backstory / Mirror /
-- Provocation / Before-After / Rate-it / Confess / Dare) without dropping
-- any of it. Function name (enforce_max_4_ping_prompts) is already stale
-- against its own prior value (6, not 4) — left as-is rather than renamed,
-- since renaming risks orphaning whatever trigger binds to it by name; the
-- number that matters is the one enforced in the body.
--
-- Global change: this raises the ceiling for every daily_prompt in the
-- system, not just the 6 Wake-pilot communities — existing prompts
-- elsewhere were authored under a 6-prompt ceiling and are unaffected
-- (still under 6), but nothing stops a future prompt anywhere from using
-- up to 10 now.
CREATE OR REPLACE FUNCTION public.enforce_max_4_ping_prompts()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
    FROM public.ping_prompts
   WHERE daily_prompt_id = NEW.daily_prompt_id
     AND active;

  IF v_count >= 10 THEN
    RAISE EXCEPTION 'A daily prompt can have at most 10 active ping-prompts.';
  END IF;

  RETURN NEW;
END;
$function$;
