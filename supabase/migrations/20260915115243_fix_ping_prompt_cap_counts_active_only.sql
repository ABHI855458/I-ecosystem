-- The cap trigger counted ALL rows for a daily_prompt_id, including
-- deactivated ones. That's wrong: the cap exists to bound how many options
-- a ping sheet can offer (6, one per archetype slot), and a deactivated
-- row contributes zero options. A deactivated stray (e.g. leftover test
-- content) was permanently burning one of the 6 slots even after being
-- turned off, which surfaced when "OVERRRATED COLLEGE PLACE" could only
-- accept 5 new active rows instead of 6.
CREATE OR REPLACE FUNCTION public.enforce_max_4_ping_prompts()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
    FROM public.ping_prompts
   WHERE daily_prompt_id = NEW.daily_prompt_id
     AND active;

  IF v_count >= 6 THEN
    RAISE EXCEPTION 'A daily prompt can have at most 6 active ping-prompts.';
  END IF;

  RETURN NEW;
END;
$$;
