-- Dual photos used to be flattened into one JPEG at post time (see
-- compositeDualPhotos), inset baked into the pixels — nothing in the feed
-- could ever know a post had two layers, so nothing could be interactive.
-- Explicit request: "make it like they can move around the other side
-- photo in the feed to see what's behind".
--
-- A NEW dual post now stores both photos separately; image_url/photo_url
-- stays the background, photo_url_secondary is the inset. inset_on_right
-- records which corner it started in (today's fixed convention is always
-- right — see DualInsetGeometry.onRight's own doc — but this makes that a
-- per-post fact instead of a hardcoded assumption, in case that default
-- ever changes again). NULL secondary means an ordinary single-layer post,
-- or an OLD dual post whose two photos were already flattened into one —
-- those keep rendering exactly as they always have, nothing migrates.
ALTER TABLE public.posts       ADD COLUMN IF NOT EXISTS photo_url_secondary text;
ALTER TABLE public.posts       ADD COLUMN IF NOT EXISTS inset_on_right boolean NOT NULL DEFAULT true;
ALTER TABLE public.group_posts ADD COLUMN IF NOT EXISTS photo_url_secondary text;
ALTER TABLE public.group_posts ADD COLUMN IF NOT EXISTS inset_on_right boolean NOT NULL DEFAULT true;
