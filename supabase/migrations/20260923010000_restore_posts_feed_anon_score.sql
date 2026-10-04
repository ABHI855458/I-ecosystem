-- REVERT of 20260921030000_posts_feed_anon_score_fingerprint.sql, by explicit
-- instruction: "restore it how it was there the posters score and level" —
-- given after the fingerprinting risk that migration documented was
-- explained again in full (unique (total_score, level) across most real
-- accounts; users_select is USING(true) so the join back to a real
-- name/email is a live, un-fixed path independent of this view). Restoring
-- ANYWAY, product decision, not a security judgment call on my part.
--
-- Reproduced VERBATIM from the live pg_get_viewdef output (pulled fresh
-- right before this migration), with ONLY author_total_score/author_level
-- reverted from the anonymous-NULLing CASE back to the original plain
-- subquery. Every other column, including the anon_photo_url/anon_name
-- CASEs added by later migrations, is left exactly as-is.
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
