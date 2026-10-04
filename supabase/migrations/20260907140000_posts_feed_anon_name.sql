-- ============================================================================
-- posts_feed.anon_name + moment_color — so an anonymous MOMENT can be shown in
-- the feed under its author's anon persona instead of being hidden entirely.
--
-- An anon Moment currently reaches no feed at all: the Friends/Everyone query
-- filters visibility IN ('everyone','friends'), and the Anon feed renders
-- ordinary post cards. So posting a Moment anonymously made it vanish
-- ("the moment didn't even appear in the feed"). The card needs a name to
-- show, and 'anonymous' as a literal is worse than the persona the rest of the
-- app already uses for anon content.
--
-- MASKED THE SAME WAY user_id IS. anon_name is returned ONLY for anonymous
-- rows — never on a named post. Returning it unconditionally would publish
-- "this real account owns this anon persona" on every ordinary post, which is
-- the exact link the anon system exists to prevent.
--
-- Everything else in the view is carried through verbatim; this is an additive
-- column on an existing view. Applied via `supabase db query --linked -f`.
-- ============================================================================

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
    -- Anon rows only. See the header.
    CASE
        WHEN visibility = 'anonymous'::text
        THEN ( SELECT NULLIF(btrim(au.anon_name), '')
                 FROM users au
                WHERE au.id = p.user_id)
        ELSE NULL::text
    END AS anon_name,
    -- Appended, not inserted mid-list: CREATE OR REPLACE VIEW can only add
    -- columns at the END (renaming an existing position fails with 42P16).
    --
    -- Was missing from this view entirely, so a Moment read through
    -- posts_feed lost the gradient its poster picked and fell back to the
    -- default palette. Not sensitive: it is a preset id, not a person.
    moment_color
   FROM posts p
  WHERE deleted_at IS NULL AND (visibility IS DISTINCT FROM 'anonymous'::text OR community_id IS NULL OR (EXISTS ( SELECT 1
           FROM community_members cm
          WHERE cm.community_id = p.community_id AND cm.user_id = auth.uid())));
