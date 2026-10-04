-- POSTS_FEED — anon_photo_url de-anonymization leak.
--
-- Found while independently re-verifying Option A (author_total_score/
-- author_level nulled on anonymous posts, already live and confirmed
-- applied). anon_photo_url was never given the same treatment: unlike
-- user_id/author_total_score/author_level/anon_name, it had no CASE at all
-- — it resolved from the real author's row on EVERY post, anonymous or not.
--
-- Proven live with a real, clean (community_id NULL, so no membership gate
-- could hide either row) pair of posts from the same user:
--
--   ANON post  -> user_id=NULL,                anon_photo_url=<persona.jpg>
--   NAMED post -> user_id=<real id, exposed>,  anon_photo_url=<persona.jpg>  (same file)
--
-- Same string on both rows, one of which names the author. Anyone who has
-- seen this person's named post — which shows anon_photo_url too, since it
-- was never gated — can match the photo against any anonymous post of
-- theirs and identify them by sight alone. This is the exact class of leak
-- anon_name is already protected against (populated ONLY on anonymous rows,
-- NULL otherwise); anon_photo_url gets the identical CASE here.
--
-- No client call site reads anon_photo_url off a non-anonymous post —
-- personal_post_card.dart/design_solo_card.dart (the named-post renderers)
-- never reference it; every read site (anon_feed_v2, anon comments, ping's
-- own anonymous-sender display) is already an anonymous-only context. So
-- nulling it on named rows removes data nothing in the app was using.
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
    inset_on_right
   FROM posts p
  WHERE deleted_at IS NULL AND (visibility IS DISTINCT FROM 'anonymous'::text OR community_id IS NULL OR (EXISTS ( SELECT 1
           FROM community_members cm
          WHERE cm.community_id = p.community_id AND cm.user_id = auth.uid()))) AND (visibility IS DISTINCT FROM 'friends'::text OR can_view_post(id));
