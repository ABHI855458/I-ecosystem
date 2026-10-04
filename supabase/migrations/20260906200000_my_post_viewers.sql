-- ---------------------------------------------------------------------------
-- my_post_viewers() — who has actually opened MY posts, pinned people first.
--
-- The feed header's eye button reads profile_views: people who visited your
-- PROFILE. It has never had any notion of posts or of pinned people, so the
-- expectation it was checked against ("does viewed-by show if the pinned
-- people viewed the post") could not be met by it at all. Post views live in
-- a different table entirely (post_views), and post_views_select_self only
-- lets you read your OWN view rows — so a post's author cannot read who
-- viewed their post from the client. This is that read.
--
-- Scoped hard to the caller's own posts (p.user_id = me), so it can only
-- ever return viewers of content you wrote. Deduped to one row per viewer —
-- their most recent view — because the panel lists people, not pageloads.
-- is_pinned is relative to the caller and sorts to the top.
-- ---------------------------------------------------------------------------

create or replace function public.my_post_viewers(p_limit integer default 60)
returns table (
  user_id uuid,
  username text,
  name text,
  avatar_url text,
  is_pinned boolean,
  post_id uuid,
  viewed_at timestamptz
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with me as (
    select id from public.users where auth_id = auth.uid()
  ),
  latest as (
    -- One row per viewer: their most recent view of anything I posted.
    select distinct on (pv.viewer_id)
      pv.viewer_id,
      pv.post_id,
      pv.created_at
    from public.post_views pv
    join public.posts p
      on p.id = pv.post_id
     and p.user_id = (select id from me)
     and p.deleted_at is null
    order by pv.viewer_id, pv.created_at desc
  )
  select
    u.id,
    u.username,
    u.name,
    u.profile_photo_url,
    exists (
      select 1
        from public.pinned_people pp
       where pp.user_id = (select id from me)
         and pp.pinned_user_id = u.id
    ) as is_pinned,
    l.post_id,
    l.created_at
  from latest l
  join public.users u on u.id = l.viewer_id
  order by 5 desc, l.created_at desc
  limit p_limit;
$$;

revoke all on function public.my_post_viewers(integer) from public;
grant execute on function public.my_post_viewers(integer) to authenticated;
