-- Guaranteed pool coverage: a prompt pool of N now takes exactly N days to
-- cycle, showing each entry once, instead of re-drawing at random daily.
--
-- WHAT WAS WRONG (measured, not theorised): the ordering salt included the
-- DAY --
--     hashtext(prompt_id || community || window || day)  ... LIMIT 1
-- so every day was an independent draw from the pool with no memory of the
-- day before. Fourteen independent draws from a 14-item pool covers ~63% of
-- it on average (coupon-collector), and that is exactly what a 14-day
-- simulation showed: Memes 11/14, Late Night Club 10/14, General 9/14,
-- Foodies 9/14, Placements & Prep 8/14, and Day Scholar just 7/14 — with
-- one Day Scholar prompt appearing three times and seven never appearing at
-- all. The 14-day authoring format assumed a rotation that the picker never
-- actually implemented.
--
-- THE FIX: drop `day` from the salt so the hash yields ONE stable
-- pseudo-random permutation per (community, window), then index into that
-- permutation with an epoch-based day counter:
--     position = day_index MOD pool_size
-- Same determinism as before (every member of a community sees the same
-- prompt on the same day, no cron job, no stored cursor), but now the
-- sequence is a rotation rather than a sample.
--
-- EPOCH: 2026-01-01, fixed. Nothing else in the schema had a day-number
-- helper (checked pg_proc for day_number/epoch/campus_day — none), so this
-- defines one inline rather than adding a table nobody else reads.
--
-- TWO DELIBERATE BEHAVIOUR CHANGES, both forced by the coverage requirement:
--
--  1. `weight` now sets a prompt's POSITION in the cycle, not its
--     frequency. "Every prompt exactly once per cycle" and "some prompts
--     more often" are mutually exclusive; the 14-day design asked for the
--     former. A heavier prompt sorts earlier in the permutation and so
--     comes up earlier in each cycle. Nothing needs changing at the call
--     sites; no prompt is ever skipped.
--
--  2. Community-specific content now always beats the universal pool when
--     it exists, instead of the old 60/40 specific/universal coin flip
--     (which was itself day-seeded). With the flip in place, ~40% of days
--     would show a universal prompt and the dedicated 14-item pool could
--     never complete a 14-day cycle. Verified this changes nothing for the
--     live Wake content: there are currently ZERO universal prompts with
--     feed_scope='anon' matching the wake window, so the old flip already
--     resolved to specific every time there. The universal pool is still
--     the fallback whenever a community has no dedicated content for a
--     window — that path is untouched.
--
-- SCOPE: this is the prompt-WITHIN-a-community picker only. It does not
-- touch prompt_bar_for_user, which decides WHICH COMMUNITY wins a window
-- (affinity x drift x freshness x social_proof x novelty) — those factors
-- are per-community and cannot differentiate inside a pool, which is why
-- they were never the cause here. Applies to every window automatically:
-- the function takes p_window as an argument, so content loaded for
-- pre_class, lunch or any other window rotates the same way with no
-- further migration.
CREATE OR REPLACE FUNCTION public.pick_window_prompt(p_community_id uuid, p_window text, p_day date, p_feed_scope text DEFAULT 'everyone'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_use_specific boolean;
  v_scope        text;
  v_salt         text;
  v_day_index    bigint;
  v_id           uuid;
BEGIN
  -- NO day component: the permutation must be identical every day, or
  -- indexing into it means nothing.
  v_salt := p_community_id::text || p_window;

  v_day_index := (p_day - DATE '2026-01-01');

  FOREACH v_scope IN ARRAY ARRAY[
    p_feed_scope,
    CASE WHEN p_feed_scope = 'anon' THEN 'everyone' ELSE 'anon' END
  ] LOOP
    -- Dedicated content first, universal only as fallback (see note 2).
    v_use_specific := TRUE;

    FOR i IN 1..2 LOOP
      SELECT x.id INTO v_id
      FROM (
        SELECT dp.id,
               row_number() OVER (
                 ORDER BY
                   -- v_salt carries the COMMUNITY, so two communities
                   -- drawing the same universal pool permute it
                   -- differently. dp.id breaks ties so the ordering is
                   -- total and therefore stable across planner changes.
                   (abs(hashtext(dp.id::text || v_salt)) % 10000)::numeric
                     / GREATEST(dp.weight, 1),
                   dp.id
               ) - 1 AS rn,
               count(*) OVER () AS pool
          FROM public.daily_prompts dp
         WHERE dp.active
           AND dp.feed_scope = v_scope
           AND (dp.expires_at IS NULL OR dp.expires_at > now())
           AND (dp.time_windows IS NULL
                OR cardinality(dp.time_windows) = 0
                OR p_window = ANY(dp.time_windows))
           AND (CASE WHEN v_use_specific
                     THEN dp.community_id = p_community_id
                     ELSE dp.community_id IS NULL END)
      ) x
      -- Double modulo: Postgres keeps the sign of the left operand, so a
      -- p_day before the epoch would otherwise produce a negative index
      -- and match no row.
      WHERE x.rn = ((v_day_index % x.pool) + x.pool) % x.pool;

      EXIT WHEN v_id IS NOT NULL;
      v_use_specific := NOT v_use_specific;
    END LOOP;

    EXIT WHEN v_id IS NOT NULL;
  END LOOP;

  RETURN v_id;
END;
$function$;
