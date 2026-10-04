-- notification_system_spec.md §1 (daily rhythm) and §7 (quiet-hours exception).
--
-- The whole spec is written in IST wall-clock windows against the real RVCE
-- day — classes 09:00–16:30, snack 11:00–11:30, lunch 12:30–14:00. This
-- migration is the single place that knows those windows; everything else
-- (triggers, the dispatcher, cron) asks these functions rather than
-- re-deriving times.
--
-- Storage model: a notifications row carries `push_after` — the earliest
-- instant its tier is allowed to interrupt. A MAJOR raised at lunch gets
-- push_after = now (send immediately); a MINOR raised mid-lecture gets
-- push_after = the next peak window, and the dispatcher picks it up then.
-- Rows with push_after IS NULL are never pushed at all, which is what keeps
-- the 59 pre-existing rows from blasting out the moment this goes live.

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS push_after    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS push_attempts INTEGER NOT NULL DEFAULT 0;

-- Dispatcher's hot path: "what is due right now."
CREATE INDEX IF NOT EXISTS notifications_push_due_idx
  ON notifications (push_after)
  WHERE push_sent_at IS NULL AND push_after IS NOT NULL;

-- ----------------------------------------
-- notification_window() — spec §1, column 1
-- ----------------------------------------
CREATE OR REPLACE FUNCTION public.notification_window(p_at TIMESTAMPTZ DEFAULT now())
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN t >= TIME '23:00' OR t < TIME '07:30' THEN 'quiet'
    WHEN t <  TIME '08:30' THEN 'wake_digest'
    WHEN t <  TIME '09:00' THEN 'pre_class'
    WHEN t <  TIME '11:00' THEN 'class_1'
    WHEN t <  TIME '11:30' THEN 'snack_peak'
    WHEN t <  TIME '12:30' THEN 'class_2'
    WHEN t <  TIME '14:00' THEN 'lunch_peak'
    WHEN t <  TIME '16:30' THEN 'class_3'
    WHEN t <  TIME '17:30' THEN 'day_end'
    WHEN t <  TIME '21:00' THEN 'evening'
    WHEN t <  TIME '22:30' THEN 'last_call'
    ELSE 'wind_down'
  END
  FROM (SELECT (p_at AT TIME ZONE 'Asia/Kolkata')::time AS t) s;
$$;

-- ----------------------------------------
-- push_allowed() — spec §1's "Rule" paragraph + §7
-- ----------------------------------------
-- MAJOR  : anywhere except deep quiet hours...
-- ...except a ping reply, which is the ONE notification §7 lets break quiet
--          hours ("the whole point of Ping is the reciprocal payoff landing
--          when it lands").
-- STANDARD: free in evening/day-end, plus both peaks, pre-class, last call
--          and the wake digest. Never during a lecture block or wind-down.
-- MINOR  : the two peak windows and the wake digest only. Never interrupts
--          anywhere else — it queues and batches.
CREATE OR REPLACE FUNCTION public.push_allowed(
  p_tier TEXT, p_type TEXT, p_at TIMESTAMPTZ DEFAULT now()
) RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_type = 'ping_answered' THEN TRUE           -- §7, the only exception
    WHEN p_tier = 'major'    THEN w <> 'quiet'
    WHEN p_tier = 'standard' THEN w IN ('wake_digest','pre_class','snack_peak',
                                        'lunch_peak','day_end','evening','last_call')
    ELSE                          w IN ('wake_digest','snack_peak','lunch_peak')
  END
  FROM (SELECT public.notification_window(p_at) AS w) s;
$$;

-- ----------------------------------------
-- next_push_slot() — when a queued row becomes sendable
-- ----------------------------------------
-- Walks the window-start times for today and tomorrow (IST) and returns the
-- first one this tier is allowed to fire in. Deliberately enumerated rather
-- than looped minute-by-minute: the answer is always one of these twelve
-- boundaries, and this stays exact across DST-free Asia/Kolkata arithmetic.
CREATE OR REPLACE FUNCTION public.next_push_slot(
  p_tier TEXT, p_type TEXT, p_at TIMESTAMPTZ DEFAULT now()
) RETURNS TIMESTAMPTZ LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $$
DECLARE
  v_day   date := (p_at AT TIME ZONE 'Asia/Kolkata')::date;
  v_slot  timestamptz;
  v_cand  timestamptz;
  v_t     time;
  v_d     int;
BEGIN
  IF public.push_allowed(p_tier, p_type, p_at) THEN
    RETURN p_at;                                   -- sendable right now
  END IF;

  FOR v_d IN 0..1 LOOP
    FOREACH v_t IN ARRAY ARRAY[
      TIME '07:30', TIME '08:30', TIME '09:00', TIME '11:00', TIME '11:30',
      TIME '12:30', TIME '14:00', TIME '16:30', TIME '17:30', TIME '21:00',
      TIME '22:30', TIME '23:00'
    ] LOOP
      v_cand := ((v_day + v_d) + v_t) AT TIME ZONE 'Asia/Kolkata';
      IF v_cand > p_at AND public.push_allowed(p_tier, p_type, v_cand) THEN
        IF v_slot IS NULL OR v_cand < v_slot THEN
          v_slot := v_cand;
        END IF;
      END IF;
    END LOOP;
    EXIT WHEN v_slot IS NOT NULL;
  END LOOP;

  -- Unreachable for the three real tiers (every tier has at least one
  -- allowed window a day), but a NULL here would silently mean "never push."
  RETURN COALESCE(v_slot, p_at + INTERVAL '1 day');
END;
$$;
