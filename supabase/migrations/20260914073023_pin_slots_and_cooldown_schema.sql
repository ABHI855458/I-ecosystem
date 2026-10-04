-- Pin slots + per-slot 7-day cooldown + slot-aware pin RPCs.
--
-- Why a SEPARATE pin_slots table instead of columns on pinned_people:
-- unpinning DELETES the pinned_people row, and the cooldown has to survive
-- that deletion (removing counts as a change). A last_changed_at column on
-- pinned_people would be erased by the very action it is meant to clock,
-- reopening the unpin-then-instantly-repin loophole.
--
-- pinned_people itself keeps its shape, so every existing identity-reveal
-- reader (is_pinned_by, post_viewers, my_post_viewers, group_post_viewers,
-- is_post_author_pinned, list_pinned_people) is untouched and keeps
-- resolving live against the table. That is what makes revocation
-- automatic: there is no derived/materialized copy of the pin set anywhere
-- in the database to go stale.

ALTER TABLE public.pinned_people
  ADD COLUMN IF NOT EXISTS slot smallint;

-- Backfill existing pins into slots 1..n, oldest first.
WITH numbered AS (
  SELECT id, row_number() OVER (PARTITION BY user_id ORDER BY created_at, id) AS rn
  FROM public.pinned_people
)
UPDATE public.pinned_people pp
   SET slot = n.rn
  FROM numbered n
 WHERE n.id = pp.id AND pp.slot IS NULL AND n.rn <= 5;

ALTER TABLE public.pinned_people
  DROP CONSTRAINT IF EXISTS pinned_people_slot_range;
ALTER TABLE public.pinned_people
  ADD CONSTRAINT pinned_people_slot_range CHECK (slot IS NULL OR slot BETWEEN 1 AND 5);

CREATE UNIQUE INDEX IF NOT EXISTS pinned_people_user_slot_uidx
  ON public.pinned_people (user_id, slot) WHERE slot IS NOT NULL;

-- The cooldown clock. One row per (user, slot) the moment that slot is
-- first touched. last_changed_at IS NULL (or no row at all) means "never
-- used" -> filling it is instant.
CREATE TABLE IF NOT EXISTS public.pin_slots (
  user_id         uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  slot            smallint    NOT NULL CHECK (slot BETWEEN 1 AND 5),
  last_changed_at timestamptz,
  PRIMARY KEY (user_id, slot)
);

-- Deny-all, exactly like pinned_people: RLS on with zero policies. The
-- SECURITY DEFINER RPCs below are the only way in.
ALTER TABLE public.pin_slots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pin_slots FROM anon, authenticated;

-- Seed clocks for pins that already existed. Uses created_at, so a pin
-- made 8 days ago is already free to change rather than being retro-locked.
INSERT INTO public.pin_slots (user_id, slot, last_changed_at)
SELECT user_id, slot, created_at AT TIME ZONE 'UTC'
FROM public.pinned_people
WHERE slot IS NOT NULL
ON CONFLICT (user_id, slot) DO NOTHING;

CREATE OR REPLACE FUNCTION public.pin_cooldown()
RETURNS interval LANGUAGE sql IMMUTABLE AS $$ SELECT interval '7 days' $$;
