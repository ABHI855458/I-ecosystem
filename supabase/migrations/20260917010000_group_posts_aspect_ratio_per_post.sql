-- Post size ("Tall"/"Classic") is a POSTER-time choice, not a viewer
-- preference — "only the poster gets to design the post size... who posts,
-- not [everyone else] in the feed, they don't get to change it." A personal
-- post already carries its own posts.aspect_ratio, written once at compose
-- time; group_posts had no equivalent column, so group posts had nowhere to
-- remember what their own poster picked.
ALTER TABLE public.group_posts ADD COLUMN IF NOT EXISTS aspect_ratio text;

COMMENT ON COLUMN public.group_posts.aspect_ratio IS
  'Width/height as decimal text, chosen by the poster at compose time (PostSizePresetPicker). Null = default (Tall, 2/3). Never a viewer preference.';
