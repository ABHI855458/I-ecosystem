-- posts_feed has no prompt_id column, so there is no read-permitted way
-- (posts_feed is the only path that can see anon posts by OTHER users —
-- posts_select's own RLS restricts an anonymous row to its own author) to
-- count how many people have answered a given daily_prompts row, which the
-- anon feed's prompt bar needs for a live "N responding" figure. Purely
-- additive — every existing column (including anon_photo_url, added by
-- unrelated work after this view was last touched here) is preserved
-- verbatim; prompt_id is appended as a new trailing column.
create or replace view posts_feed as
select
  id,
  case
    when visibility = 'anonymous' and not exists (
      select 1 from users u where u.id = p.user_id and u.auth_id = auth.uid()
    ) then null::uuid
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
  (select au.anon_photo_url from users au where au.id = p.user_id) as anon_photo_url,
  prompt_id
from posts p
where deleted_at is null
  and (
    visibility is distinct from 'anonymous'
    or community_id is null
    or exists (
      select 1 from community_members cm
      where cm.community_id = p.community_id and cm.user_id = auth.uid()
    )
  );
