-- 14-day Wake-window pilot: reduce the live community set from 99 down to
-- 6 (General, Day Scholar, Foodies, Late Night Club, Memes, Placements &
-- Prep). Soft-delete, not DELETE — `deleted_at` is the existing gating
-- column every reader already respects:
--   - prompt_bar_for_user()'s `mine` CTE: `c.deleted_at IS NULL`
--   - community_service.dart's fetchAllCommunities()
--   - select_clubs_screen.dart's own onboarding query
-- so this hides the other 93 from every picker and from the prompt engine
-- without touching their rows, their daily_prompts/ping_prompts, or any
-- existing community_members history. Reversible by clearing deleted_at.
--
-- Verified before running: real membership across all 99 was trivial
-- (max 11, on General) — this is pre-launch content curation, not a
-- live-user migration.
UPDATE communities
SET deleted_at = now(), updated_at = now()
WHERE deleted_at IS NULL
  AND id NOT IN (
    '78ce5bc0-a4d0-404b-bf9a-050f600219c9', -- General
    'cae5590a-7483-43cd-a3db-54c2d47808af', -- Day Scholar
    '6619717c-5551-49aa-afb4-ef8b524aeb30', -- Foodies
    'd77a47b0-d285-4015-bebc-d73adbc0b54e', -- Memes
    '16d6b636-fd1b-4dbd-a209-8f33e4d8bd3e', -- Placements & Prep
    '51a8ca22-5337-426c-af9b-079b5f97bba8'  -- Late Night Club
  );

-- "Day Scholar Commute" (a near-duplicate of Day Scholar, separate id
-- 1bc2b922-ca4f-4cee-9fa3-46279f2d39e9) is folded into Day Scholar rather
-- than just discarded. It had 0 members at merge time, so this is a no-op
-- today — kept generic (not just a comment) in case that changes before
-- this migration actually runs elsewhere. Commute itself is already
-- caught by the NOT IN list above, so no separate deactivation needed.
INSERT INTO community_members (community_id, user_id, joined_at)
SELECT 'cae5590a-7483-43cd-a3db-54c2d47808af', cm.user_id, cm.joined_at
FROM community_members cm
WHERE cm.community_id = '1bc2b922-ca4f-4cee-9fa3-46279f2d39e9'
ON CONFLICT (community_id, user_id) DO NOTHING;
