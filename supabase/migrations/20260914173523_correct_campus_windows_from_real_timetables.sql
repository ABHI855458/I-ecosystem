-- Campus windows corrected against the two real RVCE timetables
-- (CSE 3A Sem-3 w.e.f 07-09-2026, Physics Cycle CS-A Sem-2).
--
-- The material error: lunch sat at 12:30. On both timetables 12:30-13:30 is
-- a full teaching hour every day (Maths, ADLD, EL, DSA Lab, MA221TC), so
-- "lunch peak" prompts and standard-tier pushes were being fired into
-- class. Real lunch is 13:30-14:30.
--
-- TWO systems needed correcting, not one:
--   * prompt_windows  — drives the PROMPT BAR via current_prompt_window()
--   * notification_window() — drives PUSH gating via push_allowed()
-- They were already inconsistent with each other; both now describe the
-- same day.
--
-- NOTE on the spec's SQL: it used `ends_at` and keys lunch_peak/class_2/
-- class_3/short_break. prompt_windows has no ends_at column (a window runs
-- until the next one starts — see current_prompt_window) and its keys are
-- `lunch`/`snack`. Times are corrected here; keys are left alone because
-- prompt_bar_for_user walks them by sort_order and window_affinity_for()
-- is keyed on them, so renaming is a separate, riskier change.

UPDATE public.prompt_windows SET starts_at = '08:00' WHERE key = 'pre_class';  -- arrival, was 08:30
UPDATE public.prompt_windows SET starts_at = '13:30' WHERE key = 'lunch';      -- was 12:30 = mid-class
UPDATE public.prompt_windows SET starts_at = '18:00' WHERE key = 'evening';    -- was 17:30
-- wake 07:30, snack 11:00, day_end 16:30, last_call 21:00, wind_down 22:30
-- already match the timetables and are left as-is.

CREATE OR REPLACE FUNCTION public.notification_window(p_at timestamp with time zone DEFAULT now())
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN t >= TIME '23:30' OR t < TIME '07:30' THEN 'quiet'
    WHEN t <  TIME '08:00' THEN 'wake_digest'
    WHEN t <  TIME '09:00' THEN 'pre_class'    -- 08:00-09:00 arrival
    WHEN t <  TIME '11:00' THEN 'class_1'
    WHEN t <  TIME '11:30' THEN 'snack_peak'   -- 11:00-11:30 short break
    WHEN t <  TIME '13:30' THEN 'class_2'      -- 11:30-13:30, the long block
    WHEN t <  TIME '14:30' THEN 'lunch_peak'   -- 13:30-14:30 real lunch
    WHEN t <  TIME '16:30' THEN 'class_3'
    WHEN t <  TIME '18:00' THEN 'day_end'
    WHEN t <  TIME '21:00' THEN 'evening'
    WHEN t <  TIME '22:30' THEN 'last_call'
    ELSE 'wind_down'                            -- 22:30-23:30
  END
  FROM (SELECT (p_at AT TIME ZONE 'Asia/Kolkata')::time AS t) s;
$$;
