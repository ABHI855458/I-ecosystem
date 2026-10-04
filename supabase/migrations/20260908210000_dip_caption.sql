-- ---------------------------------------------------------------------------
-- dips.caption
--
-- Explicit request: "in dip, in anon and moments, the space where we type,
-- make it an enclosed box". Dip had no typing space at all to enclose — the
-- composer deliberately HID its caption field for this destination because
-- `dips` had nowhere to put the text (see composer_screen.dart's own note:
-- "anything typed here for that destination would silently vanish").
--
-- Additive and nullable, so every existing row and every existing reader is
-- unaffected: a Dip with no note behaves exactly as it does today.
-- ---------------------------------------------------------------------------

ALTER TABLE public.dips
  ADD COLUMN IF NOT EXISTS caption text;

-- Same cap the client enforces (composer's _captionMaxChars), restated here
-- so a direct API write can't store a caption the feed would then have to
-- truncate. NOT VALID is unnecessary: the column is new, so no row violates it.
ALTER TABLE public.dips
  DROP CONSTRAINT IF EXISTS dips_caption_len;
ALTER TABLE public.dips
  ADD CONSTRAINT dips_caption_len CHECK (caption IS NULL OR char_length(caption) <= 200);
