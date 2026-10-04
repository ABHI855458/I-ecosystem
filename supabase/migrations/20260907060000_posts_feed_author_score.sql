-- ---------------------------------------------------------------------------
-- posts_feed gains the POST AUTHOR's score and level.
--
-- The anon feed's top-left badge showed the VIEWER's own score and title on
-- every post, which says nothing about the post you're looking at. It should
-- show that post's author — "let it show the poster's of that post total
-- score and the name tag".
--
-- Safe to expose on an anonymous post: a score and a level number are not
-- identity. user_id stays masked by the same CASE it always was, and nothing
-- here lets a client map a score back to an account — two people on 180
-- points are indistinguishable. Same subquery shape the view already uses
-- for anon_photo_url.
--
-- Adding columns to a view means CREATE OR REPLACE with the full definition;
-- everything below the two new lines is the existing definition verbatim.
-- ---------------------------------------------------------------------------

create or replace view public.posts_feed as
 select id,
    case
      when visibility = 'anonymous'::text and not (exists ( select 1
         from users u
        where u.id = p.user_id and u.auth_id = auth.uid())) then null::uuid
      else user_id
    end as user_id,
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
    ( select au.anon_photo_url
        from users au
       where au.id = p.user_id) as anon_photo_url,
    prompt_id,
    -- NEW: the author's combined score + level, identity-free.
    ( select au.total_score
        from users au
       where au.id = p.user_id) as author_total_score,
    ( select au.level
        from users au
       where au.id = p.user_id) as author_level
   from posts p
  where deleted_at is null
    and (visibility is distinct from 'anonymous'::text
         or community_id is null
         or (exists ( select 1
               from community_members cm
              where cm.community_id = p.community_id
                and cm.user_id = auth.uid())));
