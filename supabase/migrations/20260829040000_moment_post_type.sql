-- Moments: make post_type actually discriminate, and give a moment its color.
--
-- posts.post_type was created as `TEXT DEFAULT 'moment'` (schema.sql), and the
-- ordinary composer path never sends the column — so EVERY post already in the
-- table reads back as post_type = 'moment'. The feed now renders
-- post_type = 'moment' with the gradient MomentCard, so without this the whole
-- feed would turn into moment cards. Flip the default to 'single' and correct
-- the existing rows; from here PostService always writes the column explicitly
-- (see post_service.dart), so the default is only a safety net.
--
-- NOTE: this rewrites already-posted test Moments to 'single' too — they were
-- indistinguishable from ordinary posts. Re-post them to get the moment card.

ALTER TABLE posts ALTER COLUMN post_type SET DEFAULT 'single';

UPDATE posts
   SET post_type = 'single'
 WHERE post_type IS NULL OR post_type = 'moment';

-- The preset gradient the poster picked, stored as a palette id — 'sunset',
-- 'violet', 'ocean', 'forest', 'ember', 'midnight' (see kMomentPalettes in
-- lib/screens/feed/widgets/moment_card.dart, the single source of truth for
-- the actual colors). Null on every non-moment post; an unknown/null id falls
-- back to the first palette client-side, so adding a palette later needs no
-- migration.
ALTER TABLE posts ADD COLUMN IF NOT EXISTS moment_color TEXT;

CREATE INDEX IF NOT EXISTS posts_post_type_idx ON posts(post_type);
