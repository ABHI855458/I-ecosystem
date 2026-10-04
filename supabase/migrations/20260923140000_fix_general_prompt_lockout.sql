-- ROOT CAUSE of "OVERRRATED COLLEGE PLACE running since morning":
-- General had exactly ONE community-specific daily_prompts row (every
-- other real community — Day Scholar, Late Night Club, Foodies,
-- Placements & Prep, Memes — has 8), and that one row was tagged with ALL
-- SEVEN time_windows.
--
-- pick_window_prompt() always tries the community-SPECIFIC pool first and
-- only falls back to the generic (community_id IS NULL, ~28 prompts) pool
-- when the specific pool is EMPTY. With exactly one row eligible in every
-- window, the specific pool's size was 1 in every window, on every day —
-- `x.rn = ((day_index % 1) + 1) % 1` is 0 regardless of day_index — so
-- General was permanently locked onto this single prompt since it was
-- created on 2026-09-08, not just today.
--
-- Verified live across all 7 windows before this fix: every one resolved
-- to this same row. No other community (checked across every one with
-- >=3 real members) has a pool-size-1 window — this is isolated to
-- General.
--
-- Fix: fold this prompt into the generic pool, exactly like its 28
-- siblings there (all of which carry NULL/empty time_windows, not an
-- explicit 7-element array — nulled here too for consistency, though
-- functionally equivalent). General now draws from that healthy 28-prompt
-- pool like a community with no dedicated set of its own is SUPPOSED to,
-- per pick_window_prompt's own fallback tier. Content is kept, not
-- deleted — it simply stops monopolizing every window.
--
-- NOT a fix for General being under-seeded relative to its peers (1
-- prompt vs. their 8) — that's a content gap, not a bug, and is for
-- whoever owns prompt content to close deliberately, the same way Late
-- Night Club's dedicated set was left for manual authoring rather than
-- invented here.
UPDATE public.daily_prompts
   SET community_id = NULL,
       time_windows = NULL
 WHERE id = '3b597e5f-27b2-4f45-97b3-24f619c1c79f'
   AND prompt_text = 'OVERRRATED COLLEGE PLACE';
