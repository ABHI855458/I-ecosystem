-- TICKET: anonymous de-anonymization via posts_feed score fingerprint.
-- LAUNCH-BLOCKING. Affects 100% of anonymous posts.
--
-- THE BUG
-- posts_feed already NULLs `user_id` on anonymous rows, but it emitted the
-- author's EXACT total_score and level beside it, with no anonymous guard:
--
--     (SELECT au.total_score FROM users au WHERE au.id = p.user_id) AS author_total_score,
--     (SELECT au.level       FROM users au WHERE au.id = p.user_id) AS author_level,
--
-- `users_select` is USING (true) and both columns carry SELECT grants to
-- `authenticated`, so any signed-in user joins the anon feed against `users`
-- and resolves the author. Verified on live data: (total_score, level) is
-- UNIQUE for 7 of 9 accounts, and all 3 live anonymous posts resolved to a
-- real name and email. No engagement required; reachable with the
-- publishable key via:
--   GET /rest/v1/posts_feed?visibility=eq.anonymous&select=author_total_score,author_level
--   GET /rest/v1/users?select=name,email,total_score,level
--
-- Masking an id is worthless while a unique fingerprint ships beside it.
--
-- THE FIX (Option A — chosen deliberately over coarsening)
-- NULL both columns on anonymous rows. The alternative considered was
-- returning a coarse tier bucket instead of the exact score, which would
-- have preserved the anon feed's score badge. Rejected: tier is only
-- non-identifying at scale. At today's 9 accounts the buckets are 7/1/1, so
-- the two outliers stay narrowable — a privacy guarantee with a "safe at
-- scale" asterisk is not a guarantee. The badge is removed from anonymous
-- posts client-side instead of being left to render a hollow 0.
--
-- Non-anonymous rows are unchanged: they still carry the real score/level,
-- which is what the Everyone/Friends surfaces use.
--
-- Everything below is reproduced VERBATIM from the live pg_get_viewdef
-- output; ONLY the two expressions above are altered (diffed line-by-line
-- before running). CREATE OR REPLACE is safe here: both columns are
-- `integer` in information_schema, and NULL::integer preserves the declared
-- type, so the view's column list/types/order are untouched.

CREATE OR REPLACE VIEW public.posts_feed AS
 SELECT id,
        CASE
            WHEN visibility = 'anonymous'::text AND NOT (EXISTS ( SELECT 1
               FROM users u
              WHERE u.id = p.user_id AND u.auth_id = auth.uid())) THEN NULL::uuid
            ELSE user_id
        END AS user_id,
    content,
    image_url,
    visibility,
    community_id,
    music_id,
    music_url,
    music_title,
    music_artist,
    prompt,
    photo_fit,
    aspect_ratio,
    post_type,
    view_count,
    created_at,
    updated_at,
    ( SELECT au.anon_photo_url
           FROM users au
          WHERE au.id = p.user_id) AS anon_photo_url,
    prompt_id,
        CASE
            WHEN visibility = 'anonymous'::text THEN NULL::integer
            ELSE ( SELECT au.total_score
               FROM users au
              WHERE au.id = p.user_id)
        END AS author_total_score,
        CASE
            WHEN visibility = 'anonymous'::text THEN NULL::integer
            ELSE ( SELECT au.level
               FROM users au
              WHERE au.id = p.user_id)
        END AS author_level,
        CASE
            WHEN visibility = 'anonymous'::text THEN ( SELECT NULLIF(btrim(au.anon_name), ''::text) AS "nullif"
               FROM users au
              WHERE au.id = p.user_id)
            ELSE NULL::text
        END AS anon_name,
    moment_color,
    video_url,
    video_duration_ms,
    photo_url_secondary,
    inset_on_right
   FROM posts p
  WHERE deleted_at IS NULL AND (visibility IS DISTINCT FROM 'anonymous'::text OR community_id IS NULL OR (EXISTS ( SELECT 1
           FROM community_members cm
          WHERE cm.community_id = p.community_id AND cm.user_id = auth.uid()))) AND (visibility IS DISTINCT FROM 'friends'::text OR can_view_post(id));;
