-- ============================================================================
-- Anon posts can go to CIRCLES as well as communities (explicit request,
-- 2026-10-03: "when doing an anon post, after clicking the photo show the
-- option to post to communities, and include circles here as well").
--
-- Circle audiences are stored exactly like a Moment's: post_audiences rows
-- with audience_kind = 'circle' (the client already writes these through
-- LocalPost.audienceCircleIds). What was missing is the READ side —
-- posts_feed decides who sees an anonymous post, and it only knew about
-- posts.community_id:
--     community_id NULL  -> everyone
--     community_id set   -> members of that community
--
-- New rule for an anonymous post (everything else unchanged):
--   * the author always sees it;
--   * members of posts.community_id see it (as before);
--   * members of any circle it was sent to see it (NEW);
--   * a post with no community AND no circle audience is still everyone's
--     (the legacy community-less posts keep their behaviour); a post with
--     no community but WITH circles is now circle-only instead of public.
--
-- Columns and author masking are byte-for-byte the live definition (read
-- with pg_get_viewdef before writing this); only the WHERE clause changes.
-- Applied with `supabase db query --linked -f` (migration ledger drift).
-- ============================================================================
BEGIN;

CREATE OR REPLACE VIEW public.posts_feed AS
 SELECT id,
        CASE
            WHEN ((visibility = 'anonymous'::text) AND (NOT (EXISTS ( SELECT 1
               FROM users u
              WHERE ((u.id = p.user_id) AND (u.auth_id = auth.uid())))))) THEN NULL::uuid
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
            WHEN (visibility = 'anonymous'::text) THEN ( SELECT au.anon_photo_url
               FROM users au
              WHERE (au.id = p.user_id))
            ELSE NULL::text
        END AS anon_photo_url,
    prompt_id,
    ( SELECT au.total_score
           FROM users au
          WHERE (au.id = p.user_id)) AS author_total_score,
    ( SELECT au.level
           FROM users au
          WHERE (au.id = p.user_id)) AS author_level,
        CASE
            WHEN (visibility = 'anonymous'::text) THEN ( SELECT NULLIF(btrim(active_anon_name(au.anon_name, au.anon_name_2, (au.active_anon_slot)::integer)), ''::text) AS "nullif"
               FROM users au
              WHERE (au.id = p.user_id))
            ELSE NULL::text
        END AS anon_name,
    moment_color,
    video_url,
    video_duration_ms,
    photo_url_secondary,
    inset_on_right,
        CASE
            WHEN ((visibility = 'anonymous'::text) AND (NOT (EXISTS ( SELECT 1
               FROM users u
              WHERE ((u.id = p.user_id) AND (u.auth_id = auth.uid())))))) THEN NULL::uuid
            ELSE partner_user_id
        END AS partner_user_id
   FROM posts p
  WHERE ((deleted_at IS NULL)
    AND ((visibility IS DISTINCT FROM 'anonymous'::text)
      -- legacy: no community and no circles -> everyone
      OR ((community_id IS NULL) AND (NOT (EXISTS ( SELECT 1
           FROM post_audiences pa
          WHERE ((pa.post_id = p.id) AND (pa.audience_kind = 'circle'::text))))))
      -- members of its community
      OR (EXISTS ( SELECT 1
           FROM community_members cm
          WHERE ((cm.community_id = p.community_id) AND (cm.user_id = auth.uid()))))
      -- the author
      OR (EXISTS ( SELECT 1
           FROM users u
          WHERE ((u.id = p.user_id) AND (u.auth_id = auth.uid()))))
      -- members of a circle it was sent to
      OR (EXISTS ( SELECT 1
           FROM post_audiences pa
             JOIN circle_members cmm ON (cmm.circle_id = pa.circle_id)
             JOIN users vu ON (vu.id = cmm.member_id)
          WHERE ((pa.post_id = p.id) AND (pa.audience_kind = 'circle'::text) AND (vu.auth_id = auth.uid())))))
    AND ((visibility IS DISTINCT FROM 'friends'::text) OR can_view_post(id)));

COMMIT;
