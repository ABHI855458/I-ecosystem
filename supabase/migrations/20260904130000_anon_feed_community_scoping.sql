-- Anon posts answering a community-scoped prompt (posts.community_id set,
-- via the dashboard's Anon > Prompts panel and the app's rotating prompt
-- bar) should only be visible, in the anon feed, to members of that
-- community. Anon posts with no community (the dashboard's "Default —
-- global fallback" prompt set) stay visible to everyone, unchanged.
--
-- posts_feed is the sole read path the anon feed uses (FeedService.
-- fetchAnonFeed/fetchProfileAnonFeed) — it runs as its owner, not the
-- caller, so it bypasses per-row RLS on `posts` entirely and is the only
-- place this restriction can be enforced today. Non-anon rows are
-- untouched (community_id is documented, in composer_screen.dart, as
-- anon-only — this clause is a no-op for every other visibility).
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
  updated_at
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
