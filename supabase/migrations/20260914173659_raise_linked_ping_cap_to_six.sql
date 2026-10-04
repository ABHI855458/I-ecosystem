-- The six-slot archetype needs SIX linked pings per prompt-bar prompt
-- (out-of-frame / honest / zoom-in / backstory / mirror / provocation,
-- 3 photo + 3 text). The guard capped it at 5 and aborted the load.
--
-- Function name kept (enforce_max_4_ping_prompts) because the trigger
-- references it and the name was already wrong by one before this change;
-- renaming is churn for no gain. The message now states the real cap.
CREATE OR REPLACE FUNCTION public.enforce_max_4_ping_prompts()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
    FROM public.ping_prompts
   WHERE daily_prompt_id = NEW.daily_prompt_id;

  IF v_count >= 6 THEN
    RAISE EXCEPTION 'A daily prompt can have at most 6 ping-prompts.';
  END IF;

  RETURN NEW;
END;
$$;
