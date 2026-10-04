-- Every circle can be renamed, Friends included (user request 2026-09-28:
-- "make it possible to change the name of the existing circles, whatever
-- they want"). Friends is identified by kind, never by name, so a rename
-- is cosmetic. It still can't be deleted and no circle can change kind.
CREATE OR REPLACE FUNCTION public.protect_circle_kind()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.kind = 'friends' THEN
      RAISE EXCEPTION 'The Friends circle cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.kind IS DISTINCT FROM OLD.kind THEN
    RAISE EXCEPTION 'A circle''s kind cannot be changed';
  END IF;
  RETURN NEW;
END $$;
