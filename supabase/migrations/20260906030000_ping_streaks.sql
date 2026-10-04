-- ============================================================================
-- PING — pairwise streaks between two people.
--
-- The friends strip in ping_page.dart has always shown a 🔥 badge, but there
-- was no pairwise-streak concept anywhere in the backend (no table, no
-- trigger, nothing computed it), so every real friend rendered 🔥0 while the
-- old fixture rows showed invented numbers. This computes it for real.
--
-- DEFINITION (chosen with the user): a day "counts" for a pair when a ping
-- between them was ANSWERED that day — i.e. a ping_replies row exists whose
-- parent ping is between exactly those two people, in either direction. A
-- ping sent and ignored does not extend a streak; the exchange has to close.
-- The streak is the run of consecutive counting days ending today or
-- yesterday (yesterday keeps it alive so it doesn't reset at midnight while
-- you still have the day to answer) — the same one-day grace and
-- Asia/Kolkata day boundary the existing group-dip streak already uses
-- (effective_group_streak, 20260903020000).
--
-- Computed on read from ping_replies history rather than stored in a table
-- with a trigger: the volume is tiny (a handful of exchanges per pair), it
-- needs no backfill, and it can never drift out of sync with the underlying
-- pings the way a denormalized counter can.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ping_streak_with(p_other) — the caller's current streak with one person.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ping_streak_with(p_other UUID)
RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  WITH me AS (SELECT public.current_user_id() AS id),
  -- Every day on which an exchange between these two closed.
  days AS (
    SELECT DISTINCT
      ((r.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date AS d
    FROM ping_replies r
    JOIN pings p ON p.id = r.ping_id
    CROSS JOIN me
    WHERE r.deleted_at IS NULL
      AND (
        (p.sender_id = me.id AND p.receiver_id = p_other)
        OR (p.sender_id = p_other AND p.receiver_id = me.id)
      )
  ),
  -- Rank days backwards from the most recent; a day that is exactly `rank`
  -- days before the anchor is still part of the unbroken run.
  ranked AS (
    SELECT d, (row_number() OVER (ORDER BY d DESC))::INT AS rn FROM days
  ),
  anchor AS (SELECT max(d) AS last_day FROM days)
  SELECT COALESCE((
    SELECT count(*)::INT
    FROM ranked, anchor
    WHERE anchor.last_day >= ((now() AT TIME ZONE 'Asia/Kolkata')::date - 1)
      AND ranked.d = anchor.last_day - (ranked.rn - 1)
  ), 0);
$$;
GRANT EXECUTE ON FUNCTION public.ping_streak_with(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- my_ping_streaks() — one row per person the caller has any ping history
-- with, so the friends strip resolves every badge in a single round trip
-- instead of N calls to ping_streak_with().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_ping_streaks()
RETURNS TABLE(other_id UUID, streak INT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
  WITH me AS (SELECT public.current_user_id() AS id),
  partners AS (
    SELECT DISTINCT
      CASE WHEN p.sender_id = me.id THEN p.receiver_id ELSE p.sender_id END AS other
    FROM pings p
    CROSS JOIN me
    WHERE (p.sender_id = me.id OR p.receiver_id = me.id)
      -- A group fan-out is not a 1:1 relationship; only person pings count
      -- toward a pairwise streak.
      AND p.group_id IS NULL
  )
  SELECT other, public.ping_streak_with(other)
  FROM partners
  WHERE other IS NOT NULL;
$$;
GRANT EXECUTE ON FUNCTION public.my_ping_streaks() TO authenticated;
