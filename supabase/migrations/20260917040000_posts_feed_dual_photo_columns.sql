-- Anon posts can now be dual-camera too (kept as two live layers instead of
-- flattening at send time, matching the friends feed) — the anon feed reads
-- through this view, which never exposed photo_url_secondary/inset_on_right
-- at all, so there was nothing for AnonFeedPost.fromRow to read even after
-- the composer stopped flattening.
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
    ( SELECT au.total_score
           FROM users au
          WHERE au.id = p.user_id) AS author_total_score,
    ( SELECT au.level
           FROM users au
          WHERE au.id = p.user_id) AS author_level,
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
          WHERE cm.community_id = p.community_id AND cm.user_id = auth.uid()))) AND (visibility IS DISTINCT FROM 'friends'::text OR can_view_post(id));
