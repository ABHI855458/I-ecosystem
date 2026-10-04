-- ============================================================================
-- Persist the anon persona photo, and surface it on the anon feed.
--
-- AnonPersonaService (lib/services/anon_persona_service.dart) held the chosen
-- persona photo in a plain in-memory field with no `users` column behind it —
-- its own doc said so ("no `users` table column for this yet"). So the photo
-- was lost on every app restart and was never visible to anybody else; the
-- anon feed drew a generated glyph avatar for every post instead.
--
-- ANONYMITY. `posts_feed` already masks user_id on anonymous rows a viewer
-- doesn't own. This adds the persona photo to that same view WITHOUT
-- unmasking anything: the URL is keyed on the storage object path, not on a
-- readable user id, and it is the image the poster deliberately chose to
-- represent their anonymous self — distinct from profile_photo_url, which is
-- never exposed here. The view keeps returning NULL user_id.
--
-- NOTE: applied via `supabase db query --linked -f`, not `db push`.
-- ============================================================================

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS anon_photo_url TEXT;

-- Recreate posts_feed with anon_photo_url added. Body is otherwise a verbatim
-- copy of the live definition (pg_get_viewdef, 2026-09-04) — the user_id
-- masking CASE and the community-membership WHERE clause are unchanged.
CREATE OR REPLACE VIEW public.posts_feed AS
  SELECT p.id,
         CASE
           WHEN p.visibility = 'anonymous'::text AND NOT (EXISTS (
             SELECT 1 FROM public.users u
              WHERE u.id = p.user_id AND u.auth_id = auth.uid()))
           THEN NULL::uuid
           ELSE p.user_id
         END AS user_id,
         p.content,
         p.image_url,
         p.visibility,
         p.community_id,
         p.music_id,
         p.music_url,
         p.music_title,
         p.music_artist,
         p.prompt,
         p.photo_fit,
         p.aspect_ratio,
         p.post_type,
         p.view_count,
         p.created_at,
         p.updated_at,
         -- The poster's chosen anon persona image. Safe to expose next to a
         -- masked user_id: it identifies a persona, not a person.
         (SELECT au.anon_photo_url FROM public.users au WHERE au.id = p.user_id)
           AS anon_photo_url
    FROM public.posts p
   WHERE p.deleted_at IS NULL
     AND (p.visibility IS DISTINCT FROM 'anonymous'::text
          OR p.community_id IS NULL
          OR (EXISTS (SELECT 1 FROM public.community_members cm
                       WHERE cm.community_id = p.community_id
                         AND cm.user_id = auth.uid())));
