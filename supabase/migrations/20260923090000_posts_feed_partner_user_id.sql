-- posts_feed never exposed posts.partner_user_id, so an "Us album" post —
-- which by definition has TWO authors — reached the client carrying only
-- one. The friends feed and the profile album had no way to name the second
-- person even though the column was sitting right there on posts.
-- Reported as both users' names not being visible on Us-album posts.
--
-- Guarded by the SAME anonymity rule user_id already uses: on an anonymous
-- post the partner is NULLed for everyone except the author themselves.
-- Without that this column would be a fresh identity leak on exactly the
-- rows the rest of this view works hardest to protect — an anonymous post
-- would name its co-author.
--
-- Appended LAST so every existing column keeps its position (CREATE OR
-- REPLACE VIEW requires it).
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
        CASE
            WHEN visibility = 'anonymous'::text THEN ( SELECT au.anon_photo_url
               FROM users au
              WHERE au.id = p.user_id)
            ELSE NULL::text
        END AS anon_photo_url,
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
    inset_on_right,
        CASE
            WHEN visibility = 'anonymous'::text AND NOT (EXISTS ( SELECT 1
               FROM users u
              WHERE u.id = p.user_id AND u.auth_id = auth.uid())) THEN NULL::uuid
            ELSE partner_user_id
        END AS partner_user_id
   FROM posts p
  WHERE deleted_at IS NULL AND (visibility IS DISTINCT FROM 'anonymous'::text OR community_id IS NULL OR (EXISTS ( SELECT 1
           FROM community_members cm
          WHERE cm.community_id = p.community_id AND cm.user_id = auth.uid()))) AND (visibility IS DISTINCT FROM 'friends'::text OR can_view_post(id));
