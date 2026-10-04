-- ============================================================================
-- Group post rules (explicit request, 2026-09-26):
--   1. A group only its creator has joined (everyone else still invited)
--      can't be posted to — same rule send_group_ping already applies.
--   2. Every NEW group post needs: at least one photo, a caption, a note,
--      a place (location) and a date (taken_at).
-- Enforced here so no client path can skip it. Existing posts are untouched
-- (INSERT only). Dips are a separate table and unaffected.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.group_post_requirements()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.group_members gm
                  WHERE gm.group_id = NEW.group_id AND gm.user_id <> NEW.user_id) THEN
    RAISE EXCEPTION 'Waiting for members to join this group.';
  END IF;
  IF NEW.photo_url IS NULL AND COALESCE(cardinality(NEW.photo_urls), 0) = 0 THEN
    RAISE EXCEPTION 'A group post needs at least one photo.';
  END IF;
  IF NULLIF(btrim(COALESCE(NEW.caption, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A group post needs a caption.';
  END IF;
  IF NULLIF(btrim(COALESCE(NEW.note, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A group post needs a note.';
  END IF;
  IF NULLIF(btrim(COALESCE(NEW.place, '')), '') IS NULL THEN
    RAISE EXCEPTION 'A group post needs a location.';
  END IF;
  IF NEW.taken_at IS NULL THEN
    RAISE EXCEPTION 'A group post needs a date.';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_group_post_requirements ON public.group_posts;
CREATE TRIGGER trg_group_post_requirements
  BEFORE INSERT ON public.group_posts
  FOR EACH ROW EXECUTE FUNCTION public.group_post_requirements();

COMMIT;
